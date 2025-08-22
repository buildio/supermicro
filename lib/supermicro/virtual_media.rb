# frozen_string_literal: true

require 'json'
require 'colorize'

module Supermicro
  module VirtualMedia
    def virtual_media
      response = authenticated_request(:get, "/redfish/v1/Managers/1/VirtualMedia")
      
      if response.status == 200
        begin
          data = JSON.parse(response.body)
          
          # Fetch each member individually since $expand doesn't work properly
          media = data["Members"].map do |member|
            member_path = member["@odata.id"]
            member_response = authenticated_request(:get, member_path)
            
            if member_response.status == 200
              m = JSON.parse(member_response.body)
            else
              next nil
            end
            # Check if media is actually inserted (not just a dummy URL)
            dummy_url = "http://0.0.0.0/dummy.iso"
            has_real_image = !m["Image"].nil? && !m["Image"].empty? && m["Image"] != dummy_url
            
            is_inserted = m["Inserted"] || 
                          has_real_image || 
                          (m["ConnectedVia"] && m["ConnectedVia"] != "NotConnected") ||
                          (m["ImageName"] && !m["ImageName"].empty?)
            
            # Override: if it's the dummy URL, consider it not inserted
            is_inserted = false if m["Image"] == dummy_url
            
            # Show media status in debug mode
            if is_inserted
              debug "#{m["Name"] || m["Id"]} #{m["ConnectedVia"]} #{m["Image"] || m["ImageName"]}", 1, :green
            else
              debug "#{m["Name"] || m["Id"]} #{m["ConnectedVia"] || 'NotConnected'}", 1, :yellow
            end
            
            action_path = m.dig("Actions", "#VirtualMedia.InsertMedia", "target")
            eject_path = m.dig("Actions", "#VirtualMedia.EjectMedia", "target")
            
            # Use a more descriptive name if the API returns generic names
            name = if m["Name"] == "Virtual Removable Media" && m["Id"]
                     "#{m["Name"]} (#{m["Id"]})"
                   else
                     m["Name"] || m["Id"]
                   end
            
            { 
              device: m["Id"],
              name: name,
              inserted: is_inserted,
              image: m["Image"] || m["ImageName"],
              connected_via: m["ConnectedVia"],
              media_types: m["MediaTypes"],
              action_path: action_path,
              eject_path: eject_path
            }
          end.compact  # Remove any nil entries
          
          return media
        rescue JSON::ParserError
          raise Error, "Failed to parse virtual media response: #{response.body}"
        end
      else
        raise Error, "Failed to get virtual media. Status code: #{response.status}"
      end
    end

    def eject_virtual_media(device: nil)
      media_list = virtual_media
      
      if device
        # Check for media with an image URL even if Inserted is false (Supermicro quirk)
        media_to_eject = media_list.find { |m| m[:device] == device && (m[:inserted] || m[:image]) }
      else
        media_to_eject = media_list.find { |m| m[:inserted] || m[:image] }
      end
      
      if media_to_eject.nil?
        debug "No media to eject#{device ? " for device #{device}" : ''}", 1, :yellow
        return false
      end
      
      debug "Ejecting #{media_to_eject[:name]} (#{media_to_eject[:image]})...", 1, :yellow
      
      # Supermicro quirk: EjectMedia action may not be available when Inserted is false
      # Try to use InsertMedia with Inserted:false to eject
      path = if media_to_eject[:eject_path] && media_to_eject[:inserted]
              media_to_eject[:eject_path]
             elsif media_to_eject[:action_path]
              # Use InsertMedia action to eject by setting Inserted to false
              media_to_eject[:action_path]
             else
              "/redfish/v1/Managers/1/VirtualMedia/#{media_to_eject[:device]}/Actions/VirtualMedia.InsertMedia"
             end
      
      # For Supermicro, use InsertMedia with a dummy image and Inserted:false to eject
      # Empty string doesn't work, so use a dummy URL
      body = if path.include?("InsertMedia")
              { 
                "Image" => "http://0.0.0.0/dummy.iso",  # Dummy URL to clear the media
                "Inserted" => false,
                "TransferMethod" => "Stream"
              }
             else
              {}
             end
      
      response = authenticated_request(
        :post,
        path,
        body: body.to_json,
        headers: { 'Content-Type': 'application/json' }
      )

      if response.status.between?(200, 299)
        debug "Media ejected successfully.", 1, :green
        return true
      else
        debug "Failed to eject media: #{response.status} - #{response.body}", 1, :red
        return false
      end
    end

    def insert_virtual_media(iso_url, device: nil)
      # Check for license if mounting HTTP/HTTPS media
      if iso_url.start_with?('http://', 'https://')
        license_info = check_virtual_media_license
        
        if license_info[:available] == false
          raise Error, "Virtual media license required: #{license_info[:message]}"
        elsif license_info[:available] == :unknown
          debug "Warning: Unable to verify virtual media license. Mount may fail if license is missing.", 1, :yellow
          debug "Supermicro requires SFT-OOB-LIC or SFT-DCMS-SINGLE for HTTP/HTTPS virtual media.", 1, :yellow
        else
          debug "Virtual media license verified: #{license_info[:licenses].join(', ')}", 2, :green
        end
      end
      
      device ||= find_best_virtual_media_device
      
      unless device
        raise Error, "No suitable virtual media device found"
      end
      
      eject_virtual_media(device: device)
      
      debug "Inserting media: #{iso_url} into #{device}...", 1, :yellow
      
      tries = 0
      max_tries = 3
      
      while tries < max_tries
        begin
          media_info = virtual_media.find { |m| m[:device] == device }
          
          unless media_info
            raise Error, "Virtual media device #{device} not found"
          end
          
          path = if media_info[:action_path]
                  media_info[:action_path]
                else
                  "/redfish/v1/Managers/1/VirtualMedia/#{device}/Actions/VirtualMedia.InsertMedia"
                end
          
          body = {
            "Image" => iso_url,
            "Inserted" => true,
            "WriteProtected" => true,
            "TransferMethod" => "Stream",
            "TransferProtocolType" => iso_url.start_with?("https") ? "HTTPS" : "HTTP"
          }
          
          response = authenticated_request(
            :post,
            path,
            body: body.to_json,
            headers: { 'Content-Type': 'application/json' }
          )
          
          if response.status == 202
            # Async operation - poll the task
            debug "Virtual media insert is async, polling task...", 1, :yellow
            
            task_result = wait_for_task_completion(response, timeout: 30)
            
            if task_result[:success]
              # Task completed, now verify the media is connected
              if verbosity == 0
                # Show spinner while verifying connection
                spinner = Spinner.new("Verifying connection", type: :dots, color: :yellow)
                spinner.start
              else
                debug "Task completed, verifying connection...", 1, :yellow
              end
              
              connected = false
              5.times do |i|
                sleep 1
                current_media = virtual_media
                inserted_media = current_media.find { |m| m[:device] == device }
                
                if inserted_media
                  if verbosity == 0
                    spinner&.update("Checking connection: #{inserted_media[:connected_via]}")
                  else
                    debug "  Status: ConnectedVia=#{inserted_media[:connected_via]}, Inserted=#{inserted_media[:inserted]}", 2
                  end
                  
                  if inserted_media[:connected_via] == "URI" && inserted_media[:inserted]
                    spinner&.stop("Media connected via URI", success: true) if verbosity == 0
                    debug "✓ Media connected successfully via URI!", 1, :green
                    connected = true
                    break
                  end
                end
              end
              
              spinner&.stop if spinner && verbosity == 0
              
              if connected
                return true
              else
                # Final check
                current_media = virtual_media
                inserted_media = current_media.find { |m| m[:device] == device }
                if inserted_media && inserted_media[:image] == iso_url
                  if inserted_media[:connected_via] == "NotConnected"
                    debug "ERROR: Media mounted but NOT CONNECTED!", 1, :red
                    debug "The ISO will NOT boot! ConnectedVia must be 'URI', not 'NotConnected'.", 1, :red
                    return false
                  else
                    debug "Media mounted with status: #{inserted_media[:connected_via]}", 1, :green
                    return true
                  end
                else
                  debug "Failed to verify media mount.", 1, :red
                  return false
                end
              end
            else
              debug "Task failed or timed out", 1, :red
              return false
            end
          elsif response.status.between?(200, 299)
            # Synchronous success (rare)
            debug "Virtual media inserted synchronously.", 1, :green
            sleep 2
            current_media = virtual_media
            inserted_media = current_media.find { |m| m[:device] == device }
            
            if inserted_media && (inserted_media[:inserted] || inserted_media[:image] == iso_url)
              if inserted_media[:connected_via] == "URI"
                debug "✓ Media connected via URI", 1, :green
                return true
              elsif inserted_media[:connected_via] == "NotConnected"
                debug "WARNING: Media mounted but not connected!", 1, :red
                return false
              else
                debug "Media mounted with status: #{inserted_media[:connected_via]}", 1, :yellow
                return true
              end
            else
              debug "Could not verify media mount", 1, :yellow
              return true
            end
          elsif response.status == 400 && response.body.include?("already")
            debug "Media already inserted, ejecting and retrying...", 1, :yellow
            eject_virtual_media(device: device)
            sleep 2
            tries += 1
          else
            debug "Failed to insert media: #{response.status} - #{response.body}", 1, :red
            tries += 1
            sleep 2
          end
        rescue => e
          debug "Error inserting media: #{e.message}", 1, :red
          tries += 1
          sleep 2
        end
      end
      
      raise Error, "Failed to insert virtual media after #{max_tries} attempts"
    end

    def find_best_virtual_media_device
      media_list = virtual_media
      
      cd_device = media_list.find { |m| 
        m[:media_types]&.include?("CD") || m[:media_types]&.include?("DVD") || 
        m[:name]&.downcase&.include?("cd") || m[:device]&.downcase&.include?("cd")
      }
      
      return cd_device[:device] if cd_device
      
      removable = media_list.find { |m|
        m[:media_types]&.include?("Removable") || 
        m[:name]&.downcase&.include?("removable")
      }
      
      return removable[:device] if removable
      
      media_list.first&.dig(:device)
    end

    def virtual_media_status
      media_list = virtual_media
      
      debug "\n=== Virtual Media Status ===", 1, :green
      
      media_list.each do |media|
        debug "\nDevice: #{media[:name]} (#{media[:device]})", 1, :cyan
        debug "  Media Types: #{media[:media_types]&.join(', ')}", 1 if media[:media_types]
        debug "  Inserted: #{media[:inserted] ? 'Yes'.green : 'No'.yellow}", 1
        debug "  Image: #{media[:image]}", 1 if media[:image]
        debug "  Connected Via: #{media[:connected_via]}", 1 if media[:connected_via]
      end
      
      media_list
    end

    def mount_iso_and_boot(iso_url, device: nil)
      debug "Mounting ISO and setting boot override...", 1, :yellow
      
      insert_virtual_media(iso_url, device: device)
      
      sleep 2
      
      begin
        require_relative 'boot'
        boot_to_cd
        debug "System will boot from virtual media on next restart.", 1, :green
        return true
      rescue => e
        debug "ISO mounted but failed to set boot override: #{e.message}", 1, :yellow
        return false
      end
    end

    def unmount_all_media
      debug "Unmounting all virtual media...", 1, :yellow
      
      media_list = virtual_media
      mounted = media_list.select { |m| m[:inserted] }
      
      if mounted.empty?
        debug "No virtual media currently mounted.", 1, :yellow
        return true
      end
      
      success = true
      mounted.each do |media|
        if eject_virtual_media(device: media[:device])
          debug "  Ejected: #{media[:name]}", 1, :green
        else
          debug "  Failed to eject: #{media[:name]}", 1, :red
          success = false
        end
      end
      
      success
    end
  end
end