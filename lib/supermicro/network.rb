# frozen_string_literal: true

require 'json'

module Supermicro
  module Network
    def get_bmc_network
      # Get the manager's ethernet interface
      response = authenticated_request(:get, "/redfish/v1/Managers/1/EthernetInterfaces/1")
      
      if response.status == 200
        data = JSON.parse(response.body)
        {
          "ipv4_address" => data.dig("IPv4Addresses", 0, "Address"),
          "subnet_mask" => data.dig("IPv4Addresses", 0, "SubnetMask"),
          "gateway" => data.dig("IPv4Addresses", 0, "Gateway"),
          "mode" => data.dig("IPv4Addresses", 0, "AddressOrigin"), # DHCP or Static
          "mac_address" => data["MACAddress"],
          "hostname" => data["HostName"],
          "fqdn" => data["FQDN"],
          "dns_servers" => data["NameServers"] || []
        }
      else
        raise Error, "Failed to get BMC network config. Status: #{response.status}"
      end
    end
    
    def set_bmc_network(ip_address: nil, subnet_mask: nil, gateway: nil, 
                        dns_primary: nil, dns_secondary: nil, hostname: nil, 
                        dhcp: false)
      
      if dhcp
        puts "Setting BMC to DHCP mode...".yellow
        body = {
          "DHCPv4" => {
            "DHCPEnabled" => true
          }
        }
      else
        puts "Configuring BMC network settings...".yellow
        body = {}
        
        # Configure static IP if provided
        if ip_address && subnet_mask
          body["IPv4StaticAddresses"] = [{
            "Address" => ip_address,
            "SubnetMask" => subnet_mask,
            "Gateway" => gateway
          }]
          puts "  IP: #{ip_address}/#{subnet_mask}".cyan
          puts "  Gateway: #{gateway}".cyan if gateway
        end
        
        # Configure DNS if provided
        if dns_primary || dns_secondary
          dns_servers = []
          dns_servers << dns_primary if dns_primary
          dns_servers << dns_secondary if dns_secondary
          body["StaticNameServers"] = dns_servers
          puts "  DNS: #{dns_servers.join(', ')}".cyan
        end
        
        # Configure hostname if provided
        if hostname
          body["HostName"] = hostname
          puts "  Hostname: #{hostname}".cyan
        end
      end
      
      response = authenticated_request(
        :patch,
        "/redfish/v1/Managers/1/EthernetInterfaces/1",
        body: body.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
      
      if response.status.between?(200, 299)
        puts "BMC network configured successfully.".green
        puts "WARNING: BMC may restart network services. Connection may be lost.".yellow if ip_address
        true
      else
        raise Error, "Failed to configure BMC network: #{response.status} - #{response.body}"
      end
    end
    
    def set_bmc_dhcp
      # Convenience method
      set_bmc_network(dhcp: true)
    end
  end
end