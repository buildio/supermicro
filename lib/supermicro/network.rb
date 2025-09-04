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
          "ipv4" => data.dig("IPv4Addresses", 0, "Address"),
          "mask" => data.dig("IPv4Addresses", 0, "SubnetMask"),
          "gateway" => data.dig("IPv4Addresses", 0, "Gateway"),
          "mode" => data.dig("IPv4Addresses", 0, "AddressOrigin"), # DHCP or Static
          "mac" => data["MACAddress"],
          "hostname" => data["HostName"],
          "fqdn" => data["FQDN"],
          "dns_servers" => data["NameServers"] || [],
          "name" => data["Id"] || "BMC",
          "speed_mbps" => data["SpeedMbps"] || 1000,
          "status" => data.dig("Status", "Health") || "OK",
          "kind" => "ethernet"
        }
      else
        raise Error, "Failed to get BMC network config. Status: #{response.status}"
      end
    end
    
    def set_bmc_network(ipv4: nil, mask: nil, gateway: nil, 
                        dns_primary: nil, dns_secondary: nil, hostname: nil, 
                        dhcp: false, wait: true)
      
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
        if ipv4 && mask
          # Must explicitly disable DHCP when setting static IP
          body["DHCPv4"] = { "DHCPEnabled" => false }
          body["IPv4StaticAddresses"] = [{
            "Address" => ipv4,
            "SubnetMask" => mask,
            "Gateway" => gateway
          }]
          puts "  IP: #{ipv4}/#{mask}".cyan
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
        puts "BMC network configuration submitted.".green
        
        # If we're changing IP and wait is enabled, handle the transition
        if ip_address && wait
          puts "Waiting for BMC to apply network changes...".yellow
          
          # Check if response contains a task/job ID
          if response.status == 202 && response.headers['Location']
            # Job was created, monitor it
            job_uri = response.headers['Location']
            puts "Monitoring job: #{job_uri}".cyan
            
            # Wait for current job to complete (on old IP)
            wait_for_network_job(job_uri)
          else
            # No job, just wait a bit for the change to apply
            sleep 5
          end
          
          # Now verify the BMC is reachable on the new IP
          puts "Verifying BMC is reachable on new IP: #{ip_address}...".yellow
          if verify_bmc_on_new_ip(ip_address, @username, @password)
            puts "BMC successfully configured and reachable on #{ip_address}".green
            
            # Update our client's host to the new IP
            @host = ip_address
            true
          else
            puts "WARNING: BMC configuration may have succeeded but cannot reach BMC on #{ip_address}".yellow
            puts "The BMC may still be applying changes or may require manual verification.".yellow
            false
          end
        else
          puts "BMC network configured successfully.".green
          puts "WARNING: BMC may restart network services. Connection may be lost.".yellow if ip_address && !wait
          true
        end
      else
        raise Error, "Failed to configure BMC network: #{response.status} - #{response.body}"
      end
    end
    
    def set_bmc_dhcp
      # Convenience method
      set_bmc_network(dhcp: true)
    end
    
    private
    
    def wait_for_network_job(job_uri, timeout: 60)
      start_time = Time.now
      
      while (Time.now - start_time) < timeout
        begin
          response = authenticated_request(:get, job_uri)
          
          if response.status == 200
            data = JSON.parse(response.body)
            state = data["TaskState"] || data["JobState"] || "Unknown"
            
            case state
            when "Completed", "OK"
              puts "Network configuration job completed successfully.".green
              return true
            when "Exception", "Critical", "Error", "Failed"
              puts "Network configuration job failed: #{state}".red
              return false
            else
              print "."
              sleep 2
            end
          else
            # Can't check status, assume it's applying
            sleep 2
          end
        rescue => e
          # Connection might be interrupted during network change
          debug "Connection error during job monitoring (expected): #{e.message}", 2
          sleep 2
        end
      end
      
      puts "\nJob monitoring timed out after #{timeout} seconds".yellow
      false
    end
    
    def verify_bmc_on_new_ip(new_ip, username, password, retries: 10, delay: 3)
      retries.times do |i|
        begin
          # Create a new connection to test the new IP
          test_conn = Faraday.new(
            url: "https://#{new_ip}",
            ssl: { verify: @verify_ssl }
          ) do |f|
            f.adapter Faraday.default_adapter
            f.response :follow_redirects
          end
          
          # Try to access the Redfish root
          response = test_conn.get('/redfish/v1/')
          
          if response.status == 200 || response.status == 401
            # BMC is responding, try to login
            login_response = test_conn.post do |req|
              req.url '/redfish/v1/SessionService/Sessions'
              req.headers['Content-Type'] = 'application/json'
              req.body = { 
                "UserName" => username, 
                "Password" => password 
              }.to_json
            end
            
            if login_response.status.between?(200, 204)
              # Successfully reached and authenticated
              # Clean up the test session
              if login_response.headers['x-auth-token']
                test_conn.delete('/redfish/v1/SessionService/Sessions') do |req|
                  req.headers['X-Auth-Token'] = login_response.headers['x-auth-token']
                end
              end
              return true
            end
          end
        rescue => e
          debug "Attempt #{i+1}/#{retries} failed: #{e.message}", 2
        end
        
        sleep delay unless i == retries - 1
      end
      
      false
    end
  end
end