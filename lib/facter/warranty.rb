require 'net/https'
require 'yaml'
require 'open-uri'
require 'rexml/document'
require 'json'

def create_dell_warranty_cache(cache)

  warranty = false
  expiration_date = Time.parse('1901-01-01T00:00:00')
  servicetag = Facter.value('serialnumber')

  begin
    # rescue in case dell.com is down
    dell_api_key     = '1adecee8a60444738f280aad1cd87d0e' # Public API key
    uri              = URI.parse("https://api.dell.com/support/v2/assetinfo/warranty/tags.json?svctags=#{servicetag}&apikey=#{dell_api_key}")
    http             = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl     = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    request          = Net::HTTP::Get.new(uri.request_uri)
    response         = http.request(request)
    r                = JSON.parse(response.body)
  rescue
  end

  begin
    r['GetAssetWarrantyResponse'] \
    ['GetAssetWarrantyResult'] \
    ['Response']['DellAsset']['Warranties']['Warranty'].each do |w|
      end_date = Time.parse(w['EndDate'])
      if expiration_date < end_date
        warranty = true
        expiration_date = end_date
      end
  end
  rescue
  end

  warranty = true if expiration_date > Time.now()

  File.open(cache, 'w') do |file|
    YAML.dump({'warranty_status' => warranty, 'expiration_date' => expiration_date.strftime("%Y-%m-%d")}, file)
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
    warranty ='Unsupported'
    # Just support for dell/lenovo so far... Contribute *hint*
    next if Facter.value('manufacturer').downcase !~ /(dell.*|lenovo)/
    next if !Facter.value('serialnumber')

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

      if Facter.value('manufacturer').downcase =~ /dell.*/
        create_dell_warranty_cache cache_file
      else
        create_lenovo_warranty_cache cache_file
      end
    end

    cache = YAML::load_file cache_file
    cache['warranty_status']
  end
end

Facter.add('warranty_expiration') do
  setcode do
    confine :kernel => ['Linux', 'Windows']
    cache = ''
    cache_file = ''

    case Facter.value('kernel')
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
