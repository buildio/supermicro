# frozen_string_literal: true

require 'json'

module Supermicro
  module Bios
    # Get BIOS attributes (public method for adapter compatibility)
    def bios_attributes
      response = authenticated_request(:get, "/redfish/v1/Systems/1/Bios")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          {
            "attributes" => data["Attributes"],
            "attribute_registry" => data["AttributeRegistry"]
          }
        rescue JSON::ParserError
          raise Error, "Failed to parse BIOS attributes response: #{response.body}"
        end
      else
        raise Error, "Failed to get BIOS attributes. Status code: #{response.status}"
      end
    end
    
    # Get just the attributes hash (private helper)
    private
    def get_bios_attributes
      result = bios_attributes
      result["attributes"] || {}
    rescue
      {}
    end
    public
    
    # Check if BIOS error prompt is disabled
    # Supermicro equivalent: WaitFor_F1_IfError should be "Disabled"
    def bios_error_prompt_disabled?
      attrs = get_bios_attributes
      
      if attrs.has_key?("WaitFor_F1_IfError")
        return attrs["WaitFor_F1_IfError"] == "Disabled"
      else
        debug "WaitFor_F1_IfError attribute not found in BIOS settings", 1, :yellow
        return false
      end
    end
    
    # Check if HDD placeholder is enabled
    # Supermicro doesn't have a direct equivalent to Dell's HddPlaceholder
    # This is a no-op that returns true for compatibility
    def bios_hdd_placeholder_enabled?
      # Supermicro automatically handles boot device placeholders
      # No explicit setting needed
      true
    end
    
    # Check if OS power control is enabled
    # Supermicro equivalent: Check power management settings
    # PowerPerformanceTuning should be "OS Controls EPB" for OS control
    def bios_os_power_control_enabled?
      attrs = get_bios_attributes
      
      # Check if OS is controlling power management
      if attrs.has_key?("PowerPerformanceTuning")
        return attrs["PowerPerformanceTuning"] == "OS Controls EPB"
      else
        # If the setting doesn't exist, assume it's not configured
        debug "PowerPerformanceTuning attribute not found in BIOS settings", 1, :yellow
        return false
      end
    end
    
    # Set BIOS error prompt behavior
    def set_bios_error_prompt(disabled: true)
      value = disabled ? "Disabled" : "Enabled"
      
      payload = {
        "Attributes" => {
          "WaitFor_F1_IfError" => value
        }
      }
      
      response = authenticated_request(
        :patch,
        "/redfish/v1/Systems/1/Bios/SD",
        body: payload.to_json,
        headers: { 'Content-Type': 'application/json' }
      )
      
      if response.status.between?(200, 299)
        debug "BIOS error prompt #{disabled ? 'disabled' : 'enabled'} successfully", 1, :green
        true
      else
        debug "Failed to set BIOS error prompt. Status: #{response.status}", 0, :red
        false
      end
    end
    
    # Set OS power control
    def set_bios_os_power_control(enabled: true)
      value = enabled ? "OS Controls EPB" : "BIOS Controls EPB"
      
      payload = {
        "Attributes" => {
          "PowerPerformanceTuning" => value
        }
      }
      
      response = authenticated_request(
        :patch,
        "/redfish/v1/Systems/1/Bios/SD",
        body: payload.to_json,
        headers: { 'Content-Type': 'application/json' }
      )
      
      if response.status.between?(200, 299)
        debug "OS power control #{enabled ? 'enabled' : 'disabled'} successfully", 1, :green
        true
      else
        debug "Failed to set OS power control. Status: #{response.status}", 0, :red
        false
      end
    end
    
    # Ensure UEFI boot mode
    def ensure_uefi_boot
      attrs = get_bios_attributes
      
      # Check current boot mode
      current_mode = attrs["BootModeSelect"]
      
      if current_mode == "UEFI"
        debug "System is already in UEFI boot mode", 1, :green
        return true
      else
        debug "System is not in UEFI boot mode (current: #{current_mode}). Setting to UEFI...", 1, :yellow
        
        # Set UEFI boot mode
        payload = {
          "Attributes" => {
            "BootModeSelect" => "UEFI"
          }
        }
        
        response = authenticated_request(
          :patch,
          "/redfish/v1/Systems/1/Bios/SD",
          body: payload.to_json,
          headers: { 'Content-Type': 'application/json' }
        )
        
        if response.status.between?(200, 299)
          debug "UEFI boot mode configured successfully", 1, :green
          debug "Note: A reboot is required for the change to take effect", 1, :yellow
          return true
        else
          debug "Failed to set UEFI boot mode. Status: #{response.status}", 0, :red
          debug "Response: #{response.body}", 2, :red
          return false
        end
      end
    end
    
    # Ensure sensible BIOS settings (Supermicro version)
    def ensure_sensible_bios!(options = {})
      # Check current state
      if bios_error_prompt_disabled? && bios_os_power_control_enabled?
        debug "BIOS settings already configured correctly", 1, :green
        return { changes_made: false }
      end
      
      debug "Configuring BIOS settings...", 1, :yellow
      
      # Build the attributes to change
      attributes = {}
      
      # Check and prepare error prompt change
      if !bios_error_prompt_disabled?
        debug "Will disable BIOS error prompt (F1 wait)", 1, :yellow
        attributes["WaitFor_F1_IfError"] = "Disabled"
      end
      
      # Check and prepare OS power control change
      if !bios_os_power_control_enabled?
        debug "Will enable OS power control", 1, :yellow
        attributes["PowerPerformanceTuning"] = "OS Controls EPB"
      end
      
      # Ensure UEFI boot mode
      attributes["BootModeSelect"] = "UEFI"
      
      # Apply all changes at once
      payload = { "Attributes" => attributes }
      
      response = authenticated_request(
        :patch,
        "/redfish/v1/Systems/1/Bios/SD",
        body: payload.to_json,
        headers: { 'Content-Type': 'application/json' }
      )
      
      if response.status.between?(200, 299)
        debug "BIOS settings configured successfully", 1, :green
        
        # Check if a reboot job was created
        if response.headers['Location']
          debug "BIOS change job created: #{response.headers['Location']}", 1, :yellow
        end
        
        return { changes_made: true }
      else
        debug "Failed to apply BIOS settings. Status: #{response.status}", 0, :red
        debug "Response: #{response.body}", 2, :red
        return { changes_made: false, error: "Failed to apply BIOS settings" }
      end
    end
    
    # Set individual BIOS attribute
    def set_bios_attribute(attribute_name, value)
      debug "Setting BIOS attribute #{attribute_name} to #{value}...", 1, :yellow
      
      body = {
        "Attributes" => {
          attribute_name => value
        }
      }
      
      response = authenticated_request(
        :patch,
        "/redfish/v1/Systems/1/Bios/SD",
        body: body.to_json,
        headers: { 'Content-Type': 'application/json' }
      )
      
      if response.status.between?(200, 299)
        debug "BIOS attribute set successfully. Changes will be applied on next reboot.", 1, :green
        return true
      else
        raise Error, "Failed to set BIOS attribute: #{response.status} - #{response.body}"
      end
    end

    def pending_bios_settings
      response = authenticated_request(:get, "/redfish/v1/Systems/1/Bios/SD")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          data["Attributes"] || {}
        rescue JSON::ParserError
          raise Error, "Failed to parse pending BIOS settings response: #{response.body}"
        end
      else
        {}
      end
    end

    def reset_bios_defaults
      debug "Resetting BIOS to defaults...", 1, :yellow
      
      response = authenticated_request(
        :post,
        "/redfish/v1/Systems/1/Bios/Actions/Bios.ResetBios",
        body: {}.to_json,
        headers: { 'Content-Type': 'application/json' }
      )
      
      if response.status.between?(200, 299)
        debug "BIOS reset to defaults successfully. Changes will be applied on next reboot.", 1, :green
        return true
      else
        raise Error, "Failed to reset BIOS: #{response.status} - #{response.body}"
      end
    end
  end
end