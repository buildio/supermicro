# frozen_string_literal: true

require 'json'
require 'colorize'

module Supermicro
  module Storage
    def storage_controllers
      response = authenticated_request(:get, "/redfish/v1/Systems/1/Storage?$expand=*($levels=1)")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          
          controllers = data["Members"].map do |controller|
            {
              "id" => controller["Id"],
              "name" => controller["Name"],
              "status" => controller.dig("Status", "Health") || "N/A",
              "storage_controllers" => controller["StorageControllers"]&.map { |sc|
                {
                  "name" => sc["Name"],
                  "manufacturer" => sc["Manufacturer"],
                  "model" => sc["Model"],
                  "firmware_version" => sc["FirmwareVersion"],
                  "speed_gbps" => sc["SpeedGbps"],
                  "supported_protocols" => sc["SupportedControllerProtocols"]
                }
              }
            }
          end
          
          return controllers
        rescue JSON::ParserError
          raise Error, "Failed to parse storage controllers response: #{response.body}"
        end
      else
        raise Error, "Failed to get storage controllers. Status code: #{response.status}"
      end
    end

    def drives
      all_drives = []
      
      controllers = storage_controllers
      
      controllers.each do |controller|
        controller_id = controller["id"]
        
        response = authenticated_request(:get, "/redfish/v1/Systems/1/Storage/#{controller_id}")
        
        if response.status == 200
          begin
            data = JSON.parse(response.body)
            
            if data["Drives"]
              data["Drives"].each do |drive_ref|
                drive_path = drive_ref["@odata.id"]
                drive_response = authenticated_request(:get, drive_path)
                
                if drive_response.status == 200
                  drive_data = JSON.parse(drive_response.body)
                  
                  all_drives << {
                    "id" => drive_data["Id"],
                    "name" => drive_data["Name"],
                    "manufacturer" => drive_data["Manufacturer"],
                    "model" => drive_data["Model"],
                    "serial" => drive_data["SerialNumber"],
                    "capacity_bytes" => drive_data["CapacityBytes"],
                    "capacity_gb" => (drive_data["CapacityBytes"].to_f / 1_000_000_000).round(2),
                    "protocol" => drive_data["Protocol"],
                    "media_type" => drive_data["MediaType"],
                    "status" => drive_data.dig("Status", "Health") || "N/A",
                    "controller" => controller_id,
                    "firmware_version" => drive_data["Revision"],
                    "rotation_speed_rpm" => drive_data["RotationSpeedRPM"],
                    "predicted_media_life_left_percent" => drive_data["PredictedMediaLifeLeftPercent"]
                  }
                end
              end
            end
          rescue JSON::ParserError
            debug "Failed to parse storage data for controller #{controller_id}", 1, :yellow
          end
        end
      end
      
      return all_drives
    end

    def volumes
      all_volumes = []
      
      controllers = storage_controllers
      
      controllers.each do |controller|
        controller_id = controller["id"]
        
        response = authenticated_request(:get, "/redfish/v1/Systems/1/Storage/#{controller_id}/Volumes?$expand=*($levels=1)")
        
        if response.status == 200
          begin
            data = JSON.parse(response.body)
            
            if data["Members"]
              data["Members"].each do |volume|
                all_volumes << {
                  "id" => volume["Id"],
                  "name" => volume["Name"],
                  "capacity_bytes" => volume["CapacityBytes"],
                  "capacity_gb" => (volume["CapacityBytes"].to_f / 1_000_000_000).round(2),
                  "volume_type" => volume["VolumeType"],
                  "raid_type" => volume["RAIDType"],
                  "status" => volume.dig("Status", "Health") || "N/A",
                  "controller" => controller_id,
                  "encrypted" => volume["Encrypted"],
                  "optimum_io_size_bytes" => volume["OptimumIOSizeBytes"]
                }
              end
            end
          rescue JSON::ParserError
            debug "Failed to parse volumes data for controller #{controller_id}", 1, :yellow
          end
        end
      end
      
      return all_volumes
    end

    def storage_summary
      puts "\n=== Storage Summary ===".green
      
      controllers = storage_controllers
      puts "\nStorage Controllers:".cyan
      controllers.each do |controller|
        puts "  #{controller['name']} (#{controller['id']})".yellow
        if controller["storage_controllers"]
          controller["storage_controllers"].each do |sc|
            puts "    - #{sc['manufacturer']} #{sc['model']}".light_cyan
            puts "      Firmware: #{sc['firmware_version']}" if sc['firmware_version']
            puts "      Speed: #{sc['speed_gbps']} Gbps" if sc['speed_gbps']
          end
        end
      end
      
      all_drives = drives
      puts "\nPhysical Drives:".cyan
      all_drives.each do |drive|
        puts "  #{drive['name']} (#{drive['id']})".yellow
        puts "    - #{drive['manufacturer']} #{drive['model']}".light_cyan
        puts "      Capacity: #{drive['capacity_gb']} GB"
        puts "      Type: #{drive['media_type']} / #{drive['protocol']}"
        puts "      Status: #{drive['status']}"
        puts "      Serial: #{drive['serial']}"
        if drive['predicted_media_life_left_percent']
          puts "      Life Remaining: #{drive['predicted_media_life_left_percent']}%"
        end
      end
      
      all_volumes = volumes
      if all_volumes.any?
        puts "\nVolumes:".cyan
        all_volumes.each do |volume|
          puts "  #{volume['name']} (#{volume['id']})".yellow
          puts "    - Capacity: #{volume['capacity_gb']} GB"
          puts "      Type: #{volume['volume_type']} / #{volume['raid_type']}"
          puts "      Status: #{volume['status']}"
          puts "      Encrypted: #{volume['encrypted']}"
        end
      end
      
      {
        "controllers" => controllers,
        "drives" => all_drives,
        "volumes" => all_volumes
      }
    end
  end
end