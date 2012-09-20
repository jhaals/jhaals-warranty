require 'net/https'
require 'yaml'
require 'open-uri'
require 'rexml/document'

def create_warranty_cache(cache)
    # Setup HTTP connection
    uri              = URI.parse('https://selfsolve.apple.com/wcResults.do')
    http             = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl     = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    request          = Net::HTTP::Post.new(uri.request_uri)

    # Prepare POST data
    request.set_form_data(
        {
        'sn'       => Facter.value('sp_serial_number'),
        'Continue' => 'Continue',
        'cn'       => '',
        'locale'   => '',
        'caller'   => '',
        'num'      => '0'
    }
    )

    # POST data and get the response
    response      = http.request(request)
    response_data = response.body

    # I apologize for this line
    warranty_status = response_data.split('warrantyPage.warrantycheck.displayHWSupportInfo').last.split('Repairs and Service Coverage: ')[1] =~ /^Active/ ? true : false

    # And this one too
    expiration_date = response_data.split('Estimated Expiration Date: ')[1].split('<')[0] if warranty_status

    File.open(cache, 'w') do |file|
        YAML.dump({'warranty_status' => warranty_status, 'expiration_date' => expiration_date}, file)
    end
end

Facter.add('warranty') do
    confine :kernel => 'Darwin'
    setcode do

        cache_file = '/var/db/.facter_warranty.fact'

        # refresh cache daily
        if File.exists?(cache_file) and Time.now < File.stat(cache_file).mtime + 86400 * 1
            Facter.debug('warranty cache: Valid')
        else
            Facter.debug('warranty cache: Outdated, recreating')
            create_warranty_cache cache_file
        end
        cache = YAML::load_file cache_file

        cache['warranty_status']
    end
end

def create_dell_warranty_cache(cache)

    warranty = 'Unknown'
    expiration_date = 'Unknown'

    begin
        # rescue in case dell.com is down
        uri = URI.parse("http://www.dell.com/support/troubleshooting/us/en/04/Index?c=us&s=bsd&cs=04&l=en&t=warranty&servicetag=#{Facter.value('serialnumber')}")
        response = Net::HTTP.get_response(uri)
    rescue
    end

    # Does the first match with html tags because there's multiple [days_left]
    match_result = /<b>\[\d+\]<\/b>/.match(response.body)

    if match_result
        # match days left in match_result.
        # I'm sorry for the ugly convertions, feel free to improve.
        warranty = false
        days_left = /\d+/.match(match_result.to_s).to_s
        if days_left.to_i != 0
            warranty = true
            end_date = DateTime.now + days_left.to_i
            expiration_date = end_date.strftime('%Y-%m-%d')
        end
    end
    File.open(cache, 'w') do |file|
        YAML.dump({'warranty_status' => warranty, 'expiration_date' => expiration_date}, file)
    end
end

def create_lenovo_warranty_cache(cache)
    # Setup HTTP connection
    uri              = URI.parse('http://support.lenovo.com/templatedata/Web%20Content/JSP/warrantyLookup.jsp')
    http             = Net::HTTP.new(uri.host, uri.port)
    request          = Net::HTTP::Post.new(uri.request_uri)

    # Prepare POST data
    request.set_form_data({ 'sysSerial' => Facter.value('serialnumber') })

    # POST data and get the response
    response      = http.request(request)
    response_data = response.body
    warranty = false
    if /Active/.match(response_data)
        warranty = true
    end

    warranty_expiration = /\d{4}-\d{2}-\d{2}/.match(response_data)

    File.open(cache, 'w') do |file|
        YAML.dump({'warranty_status' => warranty, 'expiration_date' => warranty_expiration.to_s}, file)
    end
end

Facter.add('warranty') do
    confine :kernel => ['Linux', 'Windows']
    setcode do
        warranty = 'Unsupported'
        if Facter.value('manufacturer').downcase !~ /(dell.*|lenovo)/
            # Just support for dell so far... Contribute *hint*
            next
        end
        if !Facter.value('serialnumber')
            # We require serial(serviceTag)
            next
        end

        if Facter.value('operatingsystem') == 'windows'
            cache_file = 'C:\ProgramData\PuppetLabs\puppet\var\facts\facter_warranty.fact'
        else
            cache_file = '/var/cache/.facter_warranty.fact'
        end

        # refresh cache daily
        if File.exists?(cache_file) and Time.now < File.stat(cache_file).mtime + 86400 * 1
            Facter.debug('warranty cache: Valid')
        else
            Facter.debug('warranty cache: Outdated, recreating')

            if Facter.value('manufacturer').downcase =~ /Dell.*/
                create_dell_warranty_cache cache_file
            else
                create_lenovo_warranty_cache cache_file
            end
        end

        cache = YAML::load_file cache_file

        warranty = cache['warranty_status']
        warranty
    end
end

Facter.add('warranty_expiration') do
    setcode do
        confine :kernel => ['Linux', 'Windows', 'Darwin']
        cache = ''
        cache_file = ''

        case Facter.value('kernel')
            when 'Darwin'
                cache_file = '/var/db/.facter_warranty.fact'
            when 'Linux'
                cache_file = '/var/cache/.facter_warranty.fact'
            when 'windows'
                cache_file = 'C:\ProgramData\PuppetLabs\puppet\var\facts\facter_warranty.fact'
        end

        if !File.exists?(cache_file)
            next false
        end

        cache = YAML::load_file cache_file
        cache['expiration_date']
    end
end

def create_machine_type_cache(cache)
    File.open(cache, 'w') do |file|
        if Facter.value(:sp_serial_number).length == 12
            model_number = Facter.value(:sp_serial_number)[-4,4]
        else
            model_number = Facter.value(:sp_serial_number)[-3,3]
        end

        apple_xml_data = REXML::Document.new(open('http://support-sp.apple.com/sp/product?cc=' + model_number + '&lang=en_US').string)

        apple_xml_data.root.elements.each do |element|
            if element.name == 'configCode'
                @machine_type = element.text
            end
        end
        YAML.dump({'machine_type' => @machine_type}, file)
    end
end

Facter.add('machine_type') do
  confine :kernel => 'Darwin'
  setcode do

    cache_file = '/var/db/.facter_machine_type.fact'

    # refresh cache every week
    if File.exists?(cache_file) and Time.now < File.stat(cache_file).mtime + 86400 * 7
        Facter.debug('machine_type cache: Valid')
    else
        Facter.debug('machine_type cache: Outdated, recreating')
        create_machine_type_cache cache_file
    end

    cache = YAML::load_file cache_file

    begin
        cache['machine_type']
    rescue NoMethodError
        Facter.debug('fucked up cache, create new cache and die')
        create_machine_type_cache cache_file
        exit
    end
    cache['machine_type']
  end
end
