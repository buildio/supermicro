# frozen_string_literal: true

require 'json'
require 'colorize'

module Supermicro
  module System
    def memory
      response = authenticated_request(:get, "/redfish/v1/Systems/1/Memory")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          
          memory = data["Members"].map do |member|
            # If member is just a reference, fetch the full data
            if member["@odata.id"] && !member["CapacityMiB"]
              mem_response = authenticated_request(:get, member["@odata.id"])
              if mem_response.status == 200
                m = JSON.parse(mem_response.body)
              else
                next nil
              end
            else
              m = member
            end
            
            next if m["CapacityMiB"].nil? || m["CapacityMiB"] == 0
            
            dimm_name = m["DeviceLocator"] || m["Name"]
            bank_match = /([A-Z])(\d+)/.match(dimm_name)
            
            if bank_match
              bank, index = bank_match.captures
            else
              bank = dimm_name
              index = 0
            end
            
            {
              "manufacturer" => m["Manufacturer"],
              "name" => dimm_name,
              "capacity_bytes" => m["CapacityMiB"].to_i * 1024 * 1024,
              "health" => m.dig("Status", "Health") || "N/A",
              "speed_mhz" => m["OperatingSpeedMHz"],
              "part_number" => m["PartNumber"],
              "serial" => m["SerialNumber"],
              "bank" => bank,
              "index" => index.to_i,
              "memory_device_type" => m["MemoryDeviceType"],
              "base_module_type" => m["BaseModuleType"]
            }
          end.compact
          
          return memory.sort_by { |m| [m["bank"] || "Z", m["index"] || 999] }
        rescue JSON::ParserError
          raise Error, "Failed to parse memory response: #{response.body}"
        end
      else
        raise Error, "Failed to get memory. Status code: #{response.status}"
      end
    end

    def psus
      response = authenticated_request(:get, "/redfish/v1/Chassis/1/Power")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          psus = data["PowerSupplies"].map do |psu|
            health = psu.dig("Status", "Health") || "Unknown"
            watts = psu["PowerInputWatts"] || psu["LastPowerOutputWatts"] || 0
            
            {
              "name" => psu["Name"],
              "voltage" => psu["LineInputVoltage"],
              "voltage_human" => psu["LineInputVoltageType"],
              "watts" => watts,
              "part" => psu["PartNumber"],
              "model" => psu["Model"],
              "serial" => psu["SerialNumber"],
              "status" => health,
              "manufacturer" => psu["Manufacturer"]
            }
          end
          
          return psus
        rescue JSON::ParserError
          raise Error, "Failed to parse PSU response: #{response.body}"
        end
      else
        raise Error, "Failed to get PSUs. Status code: #{response.status}"
      end
    end

    def fans
      tries = 0
      max_tries = 3
      
      while tries < max_tries
        begin
          response = authenticated_request(:get, "/redfish/v1/Chassis/1/Thermal?$expand=*($levels=1)")
          
          if response.status == 200
            data = JSON.parse(response.body)
            
            fans = data["Fans"].map do |fan|
              health = fan.dig("Status", "Health") || "Unknown"
              rpm = fan["Reading"] || fan["CurrentReading"] || 0
              
              {
                "name" => fan["Name"],
                "rpm" => rpm,
                "status" => health,
                "state" => fan.dig("Status", "State"),
                "min_rpm" => fan["MinReadingRange"],
                "max_rpm" => fan["MaxReadingRange"]
              }
            end
            
            return fans
          elsif response.status.between?(400, 499)
            power_response = authenticated_request(:get, "/redfish/v1/Systems/1?$select=PowerState")
            if power_response.status == 200 && JSON.parse(power_response.body)["PowerState"] == "Off"
              puts "WARN: System is off. Fans are not available.".yellow
              return []
            else
              raise Error, "Failed to get fans: #{response.status}"
            end
          else
            raise Error, "Failed to get fans: #{response.status}"
          end
        rescue => e
          tries += 1
          if tries >= max_tries
            raise Error, "Failed to get fans after #{max_tries} attempts: #{e.message}"
          end
          sleep 2
        end
      end
    end

    def cpus
      response = authenticated_request(:get, "/redfish/v1/Systems/1/Processors")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          
          cpus = data["Members"].map do |member|
            # Fetch each processor individually
            cpu_path = member["@odata.id"]
            cpu_response = authenticated_request(:get, cpu_path)
            
            if cpu_response.status == 200
              cpu = JSON.parse(cpu_response.body)
              
              next unless cpu["ProcessorType"] == "CPU"
              
              {
                "socket" => cpu["Socket"] || cpu["Id"],
                "model" => cpu["Model"],
                "manufacturer" => cpu["Manufacturer"],
                "cores" => cpu["TotalCores"],
                "threads" => cpu["TotalThreads"],
                "speed_mhz" => cpu["MaxSpeedMHz"],
                "health" => cpu.dig("Status", "Health") || "N/A"
              }
            else
              nil
            end
          end.compact
          
          return cpus
        rescue JSON::ParserError => e
          raise Error, "Failed to parse CPU response: #{e.message}"
        end
      else
        raise Error, "Failed to get CPUs. Status code: #{response.status}"
      end
    end

    def nics
      response = authenticated_request(:get, "/redfish/v1/Systems/1/EthernetInterfaces")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          
          # If Members are not expanded, fetch each interface individually
          nics = data["Members"].map do |member|
            # Check if this is just a reference or full data
            if member["@odata.id"] && !member["Id"]
              # It's just a reference, fetch the full data
              interface_response = authenticated_request(:get, member["@odata.id"])
              if interface_response.status == 200
                nic = JSON.parse(interface_response.body)
              else
                puts "Failed to fetch NIC #{member["@odata.id"]}: #{interface_response.status}".yellow
                next
              end
            else
              # We already have the full data
              nic = member
            end
            
            # Create adapter structure to match iDRAC format
            {
              "name" => nic["Name"],
              "manufacturer" => nic["Manufacturer"] || "Supermicro",
              "model" => nil,
              "part_number" => nil,
              "serial" => nil,
              "ports" => [
                {
                  "name" => nic["Id"],
                  "status" => nic["LinkStatus"] == "LinkDown" ? "Down" : "Up",
                  "mac" => nic["MACAddress"],
                  "ipv4" => nic.dig("IPv4Addresses", 0, "Address"),
                  "mode" => nic.dig("IPv4Addresses", 0, "AddressOrigin"), # DHCP or Static
                  "mask" => nic.dig("IPv4Addresses", 0, "SubnetMask"),
                  "port" => 0,
                  "speed_mbps" => nic["SpeedMbps"] || 0,
                  "kind" => "ethernet",
                  "linux_device" => nil
                }
              ]
            }
          end.compact  # Remove any nil entries from failed fetches
          
          return nics
        rescue JSON::ParserError
          raise Error, "Failed to parse NIC response: #{response.body}"
        end
      else
        raise Error, "Failed to get NICs. Status code: #{response.status}"
      end
    end

    def system_info
      response = authenticated_request(:get, "/redfish/v1/Systems/1")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          
          # Get Manager UUID for service tag (BMC MAC address)
          manager_uuid = nil
          manager_response = authenticated_request(:get, "/redfish/v1/Managers/1")
          if manager_response.status == 200
            manager_data = JSON.parse(manager_response.body)
            manager_uuid = manager_data["UUID"]
          end
          
          {
            "name" => data["Name"],
            "model" => data["Model"],
            "manufacturer" => data["Manufacturer"],
            "serial" => data["SerialNumber"],
            "uuid" => data["UUID"],
            "manager_uuid" => manager_uuid,
            "bios_version" => data["BiosVersion"],
            "power_state" => data["PowerState"],
            "health" => data.dig("Status", "Health"),
            "total_memory_gb" => data["MemorySummary"]["TotalSystemMemoryGiB"],
            "processor_count" => data.dig("ProcessorSummary", "Count"),
            "processor_model" => data.dig("ProcessorSummary", "Model")
          }
        rescue JSON::ParserError
          raise Error, "Failed to parse system info response: #{response.body}"
        end
      else
        raise Error, "Failed to get system info. Status code: #{response.status}"
      end
    end

    def power_consumption
      response = authenticated_request(:get, "/redfish/v1/Chassis/1/Power")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          
          power_control = data["PowerControl"].first if data["PowerControl"]
          
          {
            "consumed_watts" => power_control["PowerConsumedWatts"],
            "capacity_watts" => power_control["PowerCapacityWatts"],
            "average_watts" => power_control["PowerAverage"],
            "min_watts" => power_control["MinConsumedWatts"],
            "max_watts" => power_control["MaxConsumedWatts"]
          }
        rescue JSON::ParserError
          raise Error, "Failed to parse power consumption response: #{response.body}"
        end
      else
        raise Error, "Failed to get power consumption. Status code: #{response.status}"
      end
    end
    
    # TODO: Migrate to standardized radfish interface for uniformity across vendors
    # Once all vendor gems conform to the same interface, the radfish adapters
    # can become thin registration layers or be eliminated entirely.
    def power_consumption_watts
      data = power_consumption
      data["consumed_watts"] if data.is_a?(Hash)
    end
    
    # Get system health status
    def system_health
      response = authenticated_request(:get, "/redfish/v1/Systems/1")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          
          health = {
            "rollup" => data.dig("Status", "HealthRollup") || data.dig("Status", "Health"),
            "system" => data.dig("Status", "Health"),
            "processor" => data.dig("ProcessorSummary", "Status", "Health"),
            "memory" => data.dig("MemorySummary", "Status", "Health")
          }
          
          # Try to get storage health
          storage_response = authenticated_request(:get, "/redfish/v1/Systems/1/Storage")
          if storage_response.status == 200
            storage_data = JSON.parse(storage_response.body)
            if storage_data["Members"] && !storage_data["Members"].empty?
              # Get first storage controller's health
              storage_url = storage_data["Members"].first["@odata.id"]
              storage_detail = authenticated_request(:get, storage_url)
              if storage_detail.status == 200
                storage_detail_data = JSON.parse(storage_detail.body)
                health["storage"] = storage_detail_data.dig("Status", "Health")
              end
            end
          end
          
          health
        rescue JSON::ParserError
          raise Error, "Failed to parse system health information: #{response.body}"
        end
      else
        raise Error, "Failed to get system health. Status code: #{response.status}"
      end
    end

    def temperatures
      response = authenticated_request(:get, "/redfish/v1/Chassis/1/Thermal")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          
          temps = data["Temperatures"].map do |temp|
            {
              "name" => temp["Name"],
              "reading_celsius" => temp["ReadingCelsius"],
              "upper_threshold" => temp["UpperThresholdCritical"],
              "status" => temp.dig("Status", "Health") || "N/A"
            }
          end
          
          return temps
        rescue JSON::ParserError
          raise Error, "Failed to parse temperature response: #{response.body}"
        end
      else
        raise Error, "Failed to get temperatures. Status code: #{response.status}"
      end
    end
  end
end