require 'net/https'
require 'open-uri'
require 'rexml/document'

Facter.add('warranty') do
    confine :kernel => 'Darwin'
    setcode do
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

        if warranty_status
            # Add a new fact if there's warranty
            Facter.add('warranty_expiration') do
                confine :kernel => "Darwin"
                setcode do
                    expiration_date
                end
            end
        end
        warranty_status
    end
end

Facter.add('machine_type') do
  confine :kernel => 'Darwin'

  setcode do
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

    @machine_type
  end
end

