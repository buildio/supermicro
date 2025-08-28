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
          
          memory = data["Members"].map do |m|
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
              "model" => m["Manufacturer"],
              "name" => dimm_name,
              "capacity_bytes" => m["CapacityMiB"].to_i * 1024 * 1024,
              "health" => m.dig("Status", "Health") || "N/A",
              "speed_mhz" => m["OperatingSpeedMhz"],
              "part_number" => m["PartNumber"],
              "serial" => m["SerialNumber"],
              "bank" => bank,
              "index" => index.to_i,
              "memory_type" => m["MemoryDeviceType"]
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
      response = authenticated_request(:get, "/redfish/v1/Systems/1/EthernetInterfaces?$expand=*($levels=1)")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          
          nics = data["Members"].map do |nic|
            {
              "id" => nic["Id"],
              "name" => nic["Name"],
              "mac" => nic["MACAddress"],
              "speed_mbps" => nic["SpeedMbps"],
              "status" => nic.dig("Status", "Health") || "N/A",
              "link_status" => nic["LinkStatus"],
              "ipv4" => nic.dig("IPv4Addresses", 0, "Address"),
              "ipv6" => nic.dig("IPv6Addresses", 0, "Address")
            }
          end
          
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
          
          {
            "name" => data["Name"],
            "model" => data["Model"],
            "manufacturer" => data["Manufacturer"],
            "serial" => data["SerialNumber"],
            "uuid" => data["UUID"],
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