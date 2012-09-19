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

        Facter.add('warranty_expiration') do
            confine :kernel => "Darwin"
            setcode do
                cache['expiration_date']
            end
        end

        cache['warranty_status']
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
