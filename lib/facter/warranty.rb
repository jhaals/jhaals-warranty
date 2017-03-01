require 'net/https'
require 'yaml'
require 'open-uri'
require 'rexml/document'
require 'json'

# Hack to allow wrapping hash with array, but keeping arrays as-is:
class Object; def ensure_array; [self] end end
class Array; def ensure_array; to_a end end
class NilClass; def ensure_array; to_a end end

def create_dell_warranty_cache(cache)

  warranty        = false
  expiration_date = Time.parse('1901-01-01T00:00:00')
  start_date      = Time.now() # Push start time back and expiration forward
  servicetag      = Facter.value('serialnumber')

  Facter.debug("create_dell_warranty_cache hit")

  begin
    # rescue in case dell.com is down
    dell_api_key     = File.read("/etc/dell_api_key") # Production API key needs to be grabbed from a file
    uri              = URI.parse("https://api.dell.com/support/assetinfo/v4/getassetwarranty/#{servicetag}?apikey=#{dell_api_key}")
    Facter.debug("create_dell_warranty_cache URL is : " + uri.inspect)
    http             = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl     = true
    # TODO : Reject SSL failures
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    request          = Net::HTTP::Get.new(uri.request_uri)
    response         = http.request(request)
    r                = JSON.parse(response.body)
  rescue
  end

  Facter.debug("warranty result json : " + JSON.pretty_generate(r))
  awr = r['AssetWarrantyResponse']
  Facter.debug("warranty result 2 : " + JSON.pretty_generate(awr))
  Facter.debug("warranty result 3a : " + JSON.pretty_generate(awr[0]))
  Facter.debug("warranty result 3 : " + JSON.pretty_generate(awr[0]['AssetEntitlementData']))

  begin
    w = r['AssetWarrantyResponse'][0]['AssetEntitlementData']
    Facter.debug("warranty array type : " + w.class.to_s)
    Facter.debug("warranty array contents : " + w.inspect)
    w2 = w.ensure_array
    Facter.debug("warranty hacked array contents : " + w2.inspect)

    w2.each do |h|
      Facter.debug("warranty array elem contents : " + h.inspect)
      # Only allow ServiceLevelGroup 5 for support rather than "Dell Digital Delivery" or others?
      # TODO : Need a list of the ServiceLevelGroups and what they mean!
      if h['ServiceLevelGroup'] != 5
        Facter.debug("...skipping warranty array elem as doesn't match ServiceLevelGroup 5")
        next
      end

      new_expiration_date = Time.parse(h['EndDate'])
      Facter.debug("warranty new_expiration_date : " + new_expiration_date.inspect)
      if expiration_date < new_expiration_date 
        expiration_date = new_expiration_date
        Facter.debug("warranty expiration_date updated to new_expiration_date : " + expiration_date.inspect)
      end

      # We also want the start date for reporting purposes
      new_start_date = Time.parse(h['StartDate'])
      Facter.debug("warranty new_start_date : " + new_start_date.inspect)
      if new_start_date < start_date
        start_date = new_start_date 
        Facter.debug("warranty start_date updated to new_start_date : " + start_date.inspect)
      end
    end
  rescue
  end

  warranty = true if expiration_date > Time.now()

  File.open(cache, 'w') do |file|
    YAML.dump({'warranty_status' => warranty,
               'start_date'      => start_date.strftime("%Y-%m-%d"),
               'expiration_date' => expiration_date.strftime("%Y-%m-%d")},
              file)
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
  warranty_start = 'Unknown'

  # TODO : Read start date for Lenovo warranty too...

  File.open(cache, 'w') do |file|
    YAML.dump({'warranty_status' => warranty,
               'start_date'      => warranty_start,
               'expiration_date' => warranty_expiration.to_s},
              file)
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

Facter.add('warranty_start') do
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
    cache['start_date']
  end
end
