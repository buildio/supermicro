# frozen_string_literal: true

require 'json'

module Supermicro
  module License
    # Check if the BMC has the required licenses for virtual media
    def check_virtual_media_license
      response = authenticated_request(:get, "/redfish/v1/Managers/1/LicenseManager/QueryLicense")
      
      if response.status != 200
        debug "Unable to query license status: #{response.status}", 1, :yellow
        return { 
          available: :unknown, 
          message: "Unable to query license status",
          licenses: []
        }
      end
      
      begin
        data = JSON.parse(response.body)
        licenses = data["Licenses"] || []
        
        found_licenses = []
        has_oob = false
        has_dcms = false
        
        licenses.each do |license_json|
          # Parse the nested JSON structure
          license_data = JSON.parse(license_json) rescue nil
          next unless license_data
          
          license_name = license_data.dig("ProductKey", "Node", "LicenseName")
          next unless license_name
          
          found_licenses << license_name
          
          # Check for required licenses
          has_oob = true if license_name == "SFT-OOB-LIC"
          has_dcms = true if license_name == "SFT-DCMS-SINGLE"
        end
        
        # Virtual media requires either SFT-OOB-LIC or SFT-DCMS-SINGLE
        has_required_license = has_oob || has_dcms
        
        {
          available: has_required_license,
          licenses: found_licenses,
          message: if has_required_license
                     "Virtual media license present: #{found_licenses.join(', ')}"
                   elsif found_licenses.empty?
                     "No licenses found. Virtual media requires SFT-OOB-LIC or SFT-DCMS-SINGLE"
                   else
                     "Virtual media requires SFT-OOB-LIC or SFT-DCMS-SINGLE. Found: #{found_licenses.join(', ')}"
                   end
        }
      rescue JSON::ParserError => e
        debug "Failed to parse license response: #{e.message}", 1, :red
        { 
          available: :unknown, 
          message: "Failed to parse license response",
          licenses: []
        }
      end
    end
    
    # Get all licenses
    def licenses
      response = authenticated_request(:get, "/redfish/v1/Managers/1/LicenseManager/QueryLicense")
      
      return [] if response.status != 200
      
      begin
        data = JSON.parse(response.body)
        licenses = data["Licenses"] || []
        
        parsed_licenses = []
        licenses.each do |license_json|
          license_data = JSON.parse(license_json) rescue nil
          next unless license_data
          
          node = license_data.dig("ProductKey", "Node") || {}
          parsed_licenses << {
            id: node["LicenseID"],
            name: node["LicenseName"],
            created: node["CreateDate"]
          }
        end
        
        parsed_licenses
      rescue JSON::ParserError
        []
      end
    end
    
    # Activate a license
    def activate_license(license_key)
      response = authenticated_request(
        :post,
        "/redfish/v1/Managers/1/LicenseManager/Actions/LicenseManager.ActivateLicense",
        body: { "LicenseKey" => license_key }.to_json,
        headers: { 'Content-Type': 'application/json' }
      )
      
      if response.status.between?(200, 299)
        debug "License activated successfully", 1, :green
        true
      else
        debug "Failed to activate license: #{response.status}", 1, :red
        false
      end
    end
    
    # Clear/remove a license
    def clear_license(license_id)
      response = authenticated_request(
        :post,
        "/redfish/v1/Managers/1/LicenseManager/Actions/LicenseManager.ClearLicense",
        body: { "LicenseID" => license_id }.to_json,
        headers: { 'Content-Type': 'application/json' }
      )
      
      if response.status.between?(200, 299)
        debug "License cleared successfully", 1, :green
        true
      else
        debug "Failed to clear license: #{response.status}", 1, :red
        false
      end
    end
  end
end