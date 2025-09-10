# frozen_string_literal: true

require 'json'
require 'colorize'

module Supermicro
  module Storage
    def storage_controllers
      response = authenticated_request(:get, "/redfish/v1/Systems/1/Storage")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          
          controllers = data["Members"].map do |member|
            # If member is just a reference, fetch the full data
            if member["@odata.id"] && !member["Id"]
              controller_path = member["@odata.id"]
              controller_response = authenticated_request(:get, controller_path)
              
              if controller_response.status == 200
                controller = JSON.parse(controller_response.body)
              else
                next nil
              end
            else
              controller = member
            end
            
            controller_data = {
              "id" => controller["Id"],
              "name" => controller["Name"],
              # Extract model from first StorageController entry
              "model" => controller.dig("StorageControllers", 0, "Model") || controller["Name"],
              "firmware_version" => controller.dig("StorageControllers", 0, "FirmwareVersion"),
              "status" => controller.dig("Status", "Health") || "N/A",
              "drives_count" => controller["Drives"]&.size || 0,
              "@odata.id" => controller["@odata.id"],
              # Include full storage controller info for reference
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
            
            # Fetch drives for this controller
            if controller["Drives"] && !controller["Drives"].empty?
              controller_data["drives"] = fetch_controller_drives(controller["Id"], controller["Drives"])
            else
              controller_data["drives"] = []
            end
            
            controller_data
          end.compact
          
          return controllers
        rescue JSON::ParserError
          raise Error, "Failed to parse storage controllers response: #{response.body}"
        end
      else
        raise Error, "Failed to get storage controllers. Status code: #{response.status}"
      end
    end
    
    private
    
    def fetch_controller_drives(controller_id, drive_refs)
      drives = []
      
      drive_refs.each do |drive_ref|
        drive_path = drive_ref["@odata.id"]
        drive_response = authenticated_request(:get, drive_path)
        
        if drive_response.status == 200
          drive_data = JSON.parse(drive_response.body)
          
          drives << {
            "id" => drive_data["Id"],
            "name" => drive_data["Name"],
            "serial" => drive_data["SerialNumber"],
            "manufacturer" => drive_data["Manufacturer"],
            "model" => drive_data["Model"],
            "revision" => drive_data["Revision"],
            "capacity_bytes" => drive_data["CapacityBytes"],
            "speed_gbps" => drive_data["CapableSpeedGbs"] || drive_data["NegotiatedSpeedGbs"],
            "rotation_speed_rpm" => drive_data["RotationSpeedRPM"],
            "media_type" => drive_data["MediaType"],
            "protocol" => drive_data["Protocol"],
            "health" => drive_data.dig("Status", "Health") || "N/A",
            "temperature_celsius" => drive_data.dig("Oem", "Supermicro", "Temperature"),
            "failure_predicted" => drive_data["FailurePredicted"],
            "life_left_percent" => drive_data["PredictedMediaLifeLeftPercent"]
          }
        end
      end
      
      drives
    end
    
    public

    def drives(controller_id)
      # Following natural Redfish pattern - drives are scoped to a controller
      raise ArgumentError, "Controller ID is required" unless controller_id
      
      drives = []
      
      # Extract just the controller ID if given full path
      controller_name = controller_id.split('/').last
      
      response = authenticated_request(:get, "/redfish/v1/Systems/1/Storage/#{controller_name}")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          
          if data["Drives"]
            data["Drives"].each do |drive_ref|
              drive_path = drive_ref["@odata.id"]
              drive_response = authenticated_request(:get, drive_path)
              
              if drive_response.status == 200
                drive_data = JSON.parse(drive_response.body)
                
                drives << {
                  "id" => drive_data["Id"],
                  "name" => drive_data["Name"],
                  "serial" => drive_data["SerialNumber"],
                  "manufacturer" => drive_data["Manufacturer"],
                  "model" => drive_data["Model"],
                  "revision" => drive_data["Revision"],
                  "capacity_bytes" => drive_data["CapacityBytes"],
                  "capacity_gb" => (drive_data["CapacityBytes"].to_f / (1000**3)).round(2),
                  "speed_gbps" => drive_data["CapableSpeedGbs"] || drive_data["NegotiatedSpeedGbs"],
                  "rotation_speed_rpm" => drive_data["RotationSpeedRPM"],
                  "media_type" => drive_data["MediaType"],
                  "protocol" => drive_data["Protocol"],
                  "status" => drive_data.dig("Status", "Health") || "N/A",
                  "health" => drive_data.dig("Status", "Health") || "N/A",
                  "temperature_celsius" => drive_data.dig("Oem", "Supermicro", "Temperature"),
                  "failure_predicted" => drive_data["FailurePredicted"],
                  "life_left_percent" => drive_data["PredictedMediaLifeLeftPercent"],
                  "certified" => drive_data.dig("Oem", "Supermicro", "Certified"),
                  "@odata.id" => drive_data["@odata.id"]
                }
              end
            end
          end
        rescue JSON::ParserError
          debug "Failed to parse storage data for controller #{controller_name}", 1, :yellow
        end
      else
        raise Error, "Failed to get drives for controller #{controller_name}. Status: #{response.status}"
      end
      
      return drives
    end

    def volumes(controller_id)
      # Following natural Redfish pattern - volumes are scoped to a controller
      raise ArgumentError, "Controller ID is required" unless controller_id
      
      volumes = []
      
      # Extract just the controller ID if given full path
      controller_name = controller_id.split('/').last
      
      response = authenticated_request(:get, "/redfish/v1/Systems/1/Storage/#{controller_name}/Volumes")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          
          if data["Members"]
            data["Members"].each do |volume_ref|
              # Check if it's a reference or the actual volume data
              if volume_ref["@odata.id"]
                # It's a reference, fetch the volume
                volume_path = volume_ref["@odata.id"]
                volume_response = authenticated_request(:get, volume_path)
                
                if volume_response.status == 200
                  volume = JSON.parse(volume_response.body)
                else
                  next
                end
              else
                # It's the actual volume data
                volume = volume_ref
              end
              
              volumes << {
                "id" => volume["Id"],
                "name" => volume["Name"],
                "capacity_bytes" => volume["CapacityBytes"],
                "capacity_gb" => (volume["CapacityBytes"].to_f / (1000**3)).round(2),
                "volume_type" => volume["VolumeType"],
                "raid_type" => volume["RAIDType"],
                "status" => volume.dig("Status", "Health") || "N/A",
                "health" => volume.dig("Status", "Health") || "N/A",
                "encrypted" => volume["Encrypted"],
                "optimum_io_size_bytes" => volume["OptimumIOSizeBytes"],
                "@odata.id" => volume["@odata.id"]
              }
            end
          end
        rescue JSON::ParserError
          debug "Failed to parse volumes data for controller #{controller_name}", 1, :yellow
        end
      else
        # Some controllers may not have volumes endpoint
        debug "No volumes endpoint for controller #{controller_name} (Status: #{response.status})", 2, :yellow
      end
      
      return volumes
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
      
      # Get all drives from all controllers
      all_drives = []
      controllers.each do |controller|
        controller_drives = drives(controller["@odata.id"] || "/redfish/v1/Systems/1/Storage/#{controller['id']}")
        all_drives.concat(controller_drives) if controller_drives
      end
      
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
      
      # Get all volumes from all controllers
      all_volumes = []
      controllers.each do |controller|
        controller_volumes = volumes(controller["@odata.id"] || "/redfish/v1/Systems/1/Storage/#{controller['id']}")
        all_volumes.concat(controller_volumes) if controller_volumes
      end
      
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