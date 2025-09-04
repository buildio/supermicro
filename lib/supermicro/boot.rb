# frozen_string_literal: true

require 'json'
require 'colorize'

module Supermicro
  module Boot
    # Get boot configuration with snake_case fields
    def boot_config
      response = authenticated_request(:get, "/redfish/v1/Systems/1")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          boot_data = data["Boot"] || {}
          
          # Get boot options for resolving references
          options_map = {}
          begin
            options = boot_options
            options.each do |opt|
              options_map[opt["id"]] = opt["display_name"] || opt["name"]
            end
          rescue
            # Ignore errors fetching boot options
          end
          
          # Build boot order with resolved names
          boot_order = (boot_data["BootOrder"] || []).map do |ref|
            {
              "reference" => ref,
              "name" => options_map[ref] || ref
            }
          end
          
          # Return hash with snake_case fields
          {
            # Boot override settings (for one-time or continuous boot)
            "boot_source_override_enabled" => boot_data["BootSourceOverrideEnabled"],     # Disabled/Once/Continuous
            "boot_source_override_target" => boot_data["BootSourceOverrideTarget"],       # None/Pxe/Hdd/Cd/etc
            "boot_source_override_mode" => boot_data["BootSourceOverrideMode"],           # UEFI/Legacy
            "allowed_override_targets" => boot_data["BootSourceOverrideTarget@Redfish.AllowableValues"] || [],
            
            # Permanent boot order with resolved names
            "boot_order" => boot_order,                                                    # [{reference: "Boot0002", name: "PXE IPv4"}]
            "boot_order_refs" => boot_data["BootOrder"] || [],                            # Raw references for set_boot_order
            
            # Supermicro specific fields
            "boot_next" => boot_data["BootNext"],
            "http_boot_uri" => boot_data["HttpBootUri"],
            
            # References to other resources
            "boot_options_uri" => boot_data.dig("BootOptions", "@odata.id")
          }.compact
        rescue JSON::ParserError
          raise Error, "Failed to parse boot response: #{response.body}"
        end
      else
        raise Error, "Failed to get boot configuration. Status code: #{response.status}"
      end
    end
    
    # Get raw Redfish boot data (CamelCase)
    def boot_raw
      response = authenticated_request(:get, "/redfish/v1/Systems/1")
      
      if response.status == 200
        data = JSON.parse(response.body)
        data["Boot"] || {}
      else
        raise Error, "Failed to get boot configuration. Status code: #{response.status}"
      end
    end
    
    # Shorter alias for convenience  
    def boot
      boot_config
    end

    # Set boot override for next boot
    def set_boot_override(target, enabled: "Once", mode: nil)
      # Validate target against allowed values
      boot_data = boot
      valid_targets = boot_data["allowed_override_targets"]
      
      if valid_targets && !valid_targets.include?(target)
        debug "Invalid boot target '#{target}'. Allowed values: #{valid_targets.join(', ')}"
        raise Error, "Invalid boot target: #{target}"
      end
      
      debug "Setting boot override to #{target} (#{enabled})..."
      
      body = {
        "Boot" => {
          "BootSourceOverrideEnabled" => enabled,  # Disabled/Once/Continuous
          "BootSourceOverrideTarget" => target     # None/Pxe/Hdd/Cd/etc
        }
      }
      
      # Add boot mode if specified
      body["Boot"]["BootSourceOverrideMode"] = mode if mode
      
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

    # Get boot options collection (detailed boot devices) with snake_case
    def boot_options
      response = authenticated_request(:get, "/redfish/v1/Systems/1/BootOptions")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          options = []
          
          # Supermicro doesn't support $expand, fetch each individually
          data["Members"]&.each do |member|
            if member["@odata.id"]
              opt_response = authenticated_request(:get, member["@odata.id"])
              if opt_response.status == 200
                opt_data = JSON.parse(opt_response.body)
                options << {
                  "id" => opt_data["Id"],                                           # Boot0002
                  "boot_option_reference" => opt_data["BootOptionReference"],       # Boot0002
                  "display_name" => opt_data["DisplayName"],                        # "UEFI PXE IPv4: Intel..."
                  "name" => opt_data["DisplayName"] || opt_data["Name"],            # Alias for display_name
                  "enabled" => opt_data["BootOptionEnabled"],                       # true/false
                  "uefi_device_path" => opt_data["UefiDevicePath"],                 # UEFI device path if present
                  "description" => opt_data["Description"]
                }.compact
              end
            end
          end
          
          options
        rescue JSON::ParserError
          raise Error, "Failed to parse boot options response: #{response.body}"
        end
      else
        []
      end
    end
    
    # Alias for backwards compatibility
    def get_boot_devices
      boot_options
    end

    # Convenience methods for common boot targets
    def boot_to_pxe(enabled: "Once", mode: nil)
      set_boot_override("Pxe", enabled: enabled, mode: mode)
    end

    def boot_to_disk(enabled: "Once", mode: nil)
      set_boot_override("Hdd", enabled: enabled, mode: mode)
    end

    def boot_to_cd(enabled: "Once", mode: "UEFI")
      # Always use UEFI mode for CD boot since we're booting UEFI media
      set_boot_override("Cd", enabled: enabled, mode: mode)
    end

    def boot_to_usb(enabled: "Once", mode: nil)
      set_boot_override("Usb", enabled: enabled, mode: mode)
    end

    def boot_to_bios_setup(enabled: "Once", mode: nil)
      set_boot_override("BiosSetup", enabled: enabled, mode: mode)
    end
    
    # Set one-time boot to virtual media (CD)
    def set_one_time_boot_to_virtual_media
      debug "Setting one-time boot to virtual media...", 1, :yellow
      
      # Supermicro often needs virtual media remounted to ensure it's properly recognized
      # Check if virtual media is already mounted and remount if so
      begin
        require_relative 'virtual_media'
        vm_status = virtual_media_status
        
        if vm_status && vm_status["Inserted"]
          current_image = vm_status["Image"]
          if current_image
            debug "Remounting virtual media to ensure fresh connection...", 1, :yellow
            
            # Eject current media
            eject_virtual_media rescue nil
            sleep 2
            
            # Re-insert the media
            insert_virtual_media(current_image)
            sleep 3
            
            debug "Virtual media remounted: #{current_image}", 1, :green
          end
        end
      rescue => e
        debug "Note: Could not remount virtual media: #{e.message}", 2, :yellow
      end
      
      # Now try the standard boot override - this often works after remount
      result = boot_to_cd(enabled: "Once")
      
      if result
        debug "One-time boot to virtual media configured", 1, :green
        debug "System will boot from virtual CD on next restart", 1, :green
      else
        debug "Failed to set boot override, may need manual intervention", 1, :red
      end
      
      result
    end
    
    # Set boot order with hard drive first
    def set_boot_order_hd_first
      debug "Configuring system to boot from HD after OS installation...", 1, :yellow
      
      # First check if there's actually a hard disk present
      boot_opts = boot_options
      hd_option = boot_opts.find { |opt| 
        opt["display_name"] =~ /Hard Drive|HDD|SATA|NVMe|SSD|RAID|UEFI OS/i 
      }
      
      if hd_option
        # HD exists, set it as first in boot order
        other_options = boot_opts.select { |opt| 
          opt["enabled"] && opt["id"] != hd_option["id"]
        }.sort_by { |opt| opt["id"] }
        
        new_order = [hd_option["id"]] + other_options.map { |opt| opt["id"] }
        debug "Setting boot order with HD first: #{new_order.join(', ')}", 2, :yellow
        result = set_boot_order(new_order)
        
        if result
          debug "Boot order set with HD first", 1, :green
        end
      else
        # No HD yet - this is expected before OS install
        # DO NOT clear boot overrides as that would clear one-time boot settings
        # Just log that HD will be available after OS install
        debug "No HD found yet (expected before OS install)", 1, :yellow
        debug "HD will become available after OS installation", 1, :yellow
        debug "System will boot from HD naturally after the one-time virtual media boot", 1, :yellow
        result = true  # Return success since this is expected
      end
      
      result
    end
  end
end