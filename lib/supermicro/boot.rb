# frozen_string_literal: true

require 'json'
require 'colorize'

module Supermicro
  module Boot
    def boot_options
      response = authenticated_request(:get, "/redfish/v1/Systems/1")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          
          boot_info = data["Boot"] || {}
          
          {
            "boot_source_override_enabled" => boot_info["BootSourceOverrideEnabled"],
            "boot_source_override_target" => boot_info["BootSourceOverrideTarget"],
            "boot_source_override_mode" => boot_info["BootSourceOverrideMode"],
            "allowed_targets" => boot_info["BootSourceOverrideTarget@Redfish.AllowableValues"],
            "boot_options" => boot_info["BootOptions"],
            "boot_order" => boot_info["BootOrder"],
            "uefi_target" => boot_info["UefiTargetBootSourceOverride"]
          }
        rescue JSON::ParserError
          raise Error, "Failed to parse boot options response: #{response.body}"
        end
      else
        raise Error, "Failed to get boot options. Status code: #{response.status}"
      end
    end

    def set_boot_override(target, persistence: nil, mode: nil, persistent: false)
      valid_targets = boot_options["allowed_targets"]
      
      unless valid_targets&.include?(target)
        debug "Invalid boot target. Allowed values:"
        valid_targets&.each { |t| debug "  - #{t}" }
        raise Error, "Invalid boot target: #{target}"
      end
      
      # Handle both old persistent parameter and new persistence parameter
      enabled = if persistence
        persistence  # Use new parameter if provided
      elsif persistent
        "Continuous"  # Legacy support
      else
        "Once"  # Default
      end
      
      debug "Setting boot override to #{target} (#{enabled})..."
      
      body = {
        "Boot" => {
          "BootSourceOverrideEnabled" => enabled,
          "BootSourceOverrideTarget" => target
        }
      }
      
      # Add boot mode if specified
      if mode
        body["Boot"]["BootSourceOverrideMode"] = mode
      end
      
      response = authenticated_request(
        :patch,
        "/redfish/v1/Systems/1",
        body: body.to_json,
        headers: { 'Content-Type': 'application/json' }
      )
      
      if response.status.between?(200, 299)
        debug "Boot override set successfully."
        return true
      else
        raise Error, "Failed to set boot override: #{response.status} - #{response.body}"
      end
    end
    
    def configure_boot_settings(persistence: nil, mode: nil)
      debug "Configuring boot settings..."
      
      body = { "Boot" => {} }
      
      if persistence
        body["Boot"]["BootSourceOverrideEnabled"] = persistence
      end
      
      if mode
        body["Boot"]["BootSourceOverrideMode"] = mode
      end
      
      return false if body["Boot"].empty?
      
      response = authenticated_request(
        :patch,
        "/redfish/v1/Systems/1",
        body: body.to_json,
        headers: { 'Content-Type': 'application/json' }
      )
      
      if response.status.between?(200, 299)
        debug "Boot settings configured successfully."
        return true
      else
        raise Error, "Failed to configure boot settings: #{response.status} - #{response.body}"
      end
    end

    def clear_boot_override
      puts "Clearing boot override...".yellow
      
      body = {
        "Boot" => {
          "BootSourceOverrideEnabled" => "Disabled"
        }
      }
      
      response = authenticated_request(
        :patch,
        "/redfish/v1/Systems/1",
        body: body.to_json,
        headers: { 'Content-Type': 'application/json' }
      )
      
      if response.status.between?(200, 299)
        puts "Boot override cleared successfully.".green
        return true
      else
        raise Error, "Failed to clear boot override: #{response.status} - #{response.body}"
      end
    end

    def set_boot_order(devices)
      puts "Setting boot order...".yellow
      
      body = {
        "Boot" => {
          "BootOrder" => devices
        }
      }
      
      response = authenticated_request(
        :patch,
        "/redfish/v1/Systems/1",
        body: body.to_json,
        headers: { 'Content-Type': 'application/json' }
      )
      
      if response.status.between?(200, 299)
        puts "Boot order set successfully.".green
        return true
      else
        raise Error, "Failed to set boot order: #{response.status} - #{response.body}"
      end
    end

    def get_boot_devices
      response = authenticated_request(:get, "/redfish/v1/Systems/1/BootOptions?$expand=*($levels=1)")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          
          devices = data["Members"]&.map do |device|
            {
              "id" => device["Id"],
              "name" => device["DisplayName"] || device["Name"],
              "description" => device["Description"],
              "boot_option_reference" => device["BootOptionReference"],
              "enabled" => device["BootOptionEnabled"],
              "uefi_device_path" => device["UefiDevicePath"]
            }
          end || []
          
          return devices
        rescue JSON::ParserError
          raise Error, "Failed to parse boot devices response: #{response.body}"
        end
      else
        []
      end
    end

    def boot_to_pxe(persistence: nil, mode: nil)
      set_boot_override("Pxe", persistence: persistence, mode: mode)
    end

    def boot_to_disk(persistence: nil, mode: nil)
      set_boot_override("Hdd", persistence: persistence, mode: mode)
    end

    def boot_to_cd(persistence: nil, mode: nil)
      set_boot_override("Cd", persistence: persistence, mode: mode)
    end

    def boot_to_usb(persistence: nil, mode: nil)
      set_boot_override("Usb", persistence: persistence, mode: mode)
    end

    def boot_to_bios_setup(persistence: nil, mode: nil)
      set_boot_override("BiosSetup", persistence: persistence, mode: mode)
    end
  end
end