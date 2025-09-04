# frozen_string_literal: true

require 'json'
require 'colorize'

module Supermicro
  module SystemConfig
    # BIOS methods have been moved to the Bios module for better organization
    # Use client.bios_attributes, client.set_bios_attribute, etc. instead

    def manager_network_protocol
      response = authenticated_request(:get, "/redfish/v1/Managers/1/NetworkProtocol")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          
          protocols = {}
          ["HTTP", "HTTPS", "IPMI", "SSH", "SNMP", "VirtualMedia", "KVMIP", "NTP", "Telnet"].each do |proto|
            if data[proto]
              protocols[proto.downcase] = {
                "enabled" => data[proto]["ProtocolEnabled"],
                "port" => data[proto]["Port"]
              }
            end
          end
          
          protocols
        rescue JSON::ParserError
          raise Error, "Failed to parse network protocol response: #{response.body}"
        end
      else
        raise Error, "Failed to get network protocols. Status code: #{response.status}"
      end
    end

    def set_network_protocol(protocol, enabled:, port: nil)
      puts "Configuring #{protocol} protocol...".yellow
      
      proto_key = protocol.upcase
      body = {
        proto_key => {
          "ProtocolEnabled" => enabled
        }
      }
      
      body[proto_key]["Port"] = port if port
      
      response = authenticated_request(
        :patch,
        "/redfish/v1/Managers/1/NetworkProtocol",
        body: body.to_json,
        headers: { 'Content-Type': 'application/json' }
      )
      
      if response.status.between?(200, 299)
        puts "Network protocol configured successfully.".green
        return true
      else
        raise Error, "Failed to configure network protocol: #{response.status} - #{response.body}"
      end
    end

    def manager_info
      response = authenticated_request(:get, "/redfish/v1/Managers/1")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          
          {
            "name" => data["Name"],
            "model" => data["Model"],
            "firmware_version" => data["FirmwareVersion"],
            "uuid" => data["UUID"],
            "status" => data.dig("Status", "Health"),
            "datetime" => data["DateTime"],
            "datetime_local_offset" => data["DateTimeLocalOffset"]
          }
        rescue JSON::ParserError
          raise Error, "Failed to parse manager info response: #{response.body}"
        end
      else
        raise Error, "Failed to get manager info. Status code: #{response.status}"
      end
    end

    def set_manager_datetime(datetime_str)
      puts "Setting BMC datetime to #{datetime_str}...".yellow
      
      body = {
        "DateTime" => datetime_str
      }
      
      response = authenticated_request(
        :patch,
        "/redfish/v1/Managers/1",
        body: body.to_json,
        headers: { 'Content-Type': 'application/json' }
      )
      
      if response.status.between?(200, 299)
        puts "DateTime set successfully.".green
        return true
      else
        raise Error, "Failed to set datetime: #{response.status} - #{response.body}"
      end
    end

    def reset_manager
      puts "Resetting BMC...".yellow
      
      response = authenticated_request(
        :post,
        "/redfish/v1/Managers/1/Actions/Manager.Reset",
        body: { "ResetType": "GracefulRestart" }.to_json,
        headers: { 'Content-Type': 'application/json' }
      )
      
      if response.status.between?(200, 299)
        puts "BMC reset initiated successfully.".green
        return true
      else
        raise Error, "Failed to reset BMC: #{response.status} - #{response.body}"
      end
    end
  end
end