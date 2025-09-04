require 'spec_helper'
require 'support/redfish_fixtures'

RSpec.describe Supermicro::Bios do
  include RedfishFixtures
  
  let(:client) do
    Class.new do
      include Supermicro::Bios
      
      def authenticated_request(method, endpoint, options = {})
        # Mock implementation for testing
      end
      
      def debug(message, level = 1, color = :white)
        # Mock implementation for testing
      end
    end.new
  end
  
  describe '#bios_attributes' do
    it 'returns BIOS attributes from the system' do
      # Mock the authenticated_request to return our fixture
      response = mock_redfish_response('bios')
      allow(client).to receive(:authenticated_request)
        .with(:get, "/redfish/v1/Systems/1/Bios")
        .and_return(response)
      
      result = client.bios_attributes
      
      expect(result).to have_key('attributes')
      expect(result).to have_key('attribute_registry')
      expect(result['attributes']).to be_a(Hash)
      expect(result['attributes'].keys.size).to be > 50  # Should have many BIOS settings
    end
  end
  
  describe '#bios_error_prompt_disabled?' do
    it 'checks if F1 error prompt is disabled' do
      # Mock the bios_attributes call
      allow(client).to receive(:bios_attributes).and_return(
        load_fixture('bios')
      )
      
      result = client.bios_error_prompt_disabled?
      expect(result).to be_in([true, false])  # Should return a boolean
    end
  end
  
  describe '#bios_os_power_control_enabled?' do
    it 'checks if OS power control is enabled' do
      # Mock the bios_attributes call
      allow(client).to receive(:bios_attributes).and_return(
        load_fixture('bios')
      )
      
      result = client.bios_os_power_control_enabled?
      expect(result).to be_in([true, false])  # Should return a boolean
    end
  end
end