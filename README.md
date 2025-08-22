# Supermicro Redfish Ruby Client

A Ruby client library for interacting with Supermicro BMC (Baseboard Management Controller) via the Redfish API.

## Features

This gem provides a Ruby interface to manage Supermicro servers through their BMC, offering the same functionality as the iDRAC gem but for Supermicro hardware:

### Inventory Management
- **System Information**: Model, serial number, BIOS version, UUID
- **CPU**: Socket information, cores, threads, speed
- **Memory**: DIMMs capacity, speed, health status
- **Storage**: Controllers, physical drives, volumes/RAID configuration
- **Network**: NICs with MAC addresses, link status, IP configuration
- **Power Supplies**: Status, wattage, health monitoring
- **Thermal**: Fan speeds, temperature sensors
- **Power Consumption**: Current usage, capacity

### Configuration
- **Boot Order**: Set boot device priority
- **Boot Override**: One-time or persistent boot device selection
- **BIOS Settings**: Read and modify BIOS attributes
- **Network Protocols**: Configure BMC network services
- **User Management**: Create, modify, delete BMC users

### Virtual Media
- **Mount/Unmount ISO**: Attach HTTP-served ISO images
- **Virtual Media Status**: Check mounted media
- **Boot from Virtual Media**: Combined mount and boot configuration

### Power Management
- **Power Status**: Check current power state
- **Power Control**: On, Off, Restart, Power Cycle
- **Graceful Shutdown**: Attempt graceful OS shutdown

### Monitoring & Logging
- **System Event Log**: View and clear SEL entries
- **Jobs/Tasks**: Monitor long-running operations
- **Active Sessions**: View current BMC sessions

## Installation

Add to your Gemfile:

```ruby
gem 'supermicro', path: './supermicro'
```

Or install directly:

```bash
cd supermicro
bundle install
```

## Usage

### Basic Connection

```ruby
require 'supermicro'

# Create a client
client = Supermicro.new(
  host: '192.168.1.100',
  username: 'admin',
  password: 'password',
  verify_ssl: false
)

# Or use block form with automatic session cleanup
Supermicro.connect(
  host: '192.168.1.100',
  username: 'admin',
  password: 'password'
) do |client|
  # Your code here
  puts client.power_status
end
```

### Power Management

```ruby
# Check power status
status = client.power_status  # => "On" or "Off"

# Power operations
client.power_on
client.power_off
client.power_restart
client.power_cycle
```

### System Inventory

```ruby
# Get system information
info = client.system_info

# Get CPU information
cpus = client.cpus

# Get memory information
memory = client.memory

# Get storage summary
storage = client.storage_summary

# Get thermal information
fans = client.fans
temps = client.temperatures
```

### Virtual Media

```ruby
# Check virtual media status
media = client.virtual_media_status

# Mount an ISO
client.insert_virtual_media("http://example.com/os.iso")

# Unmount all media
client.unmount_all_media

# Mount ISO and set boot override
client.mount_iso_and_boot("http://example.com/os.iso")
```

### Boot Configuration

```ruby
# Get boot options
options = client.boot_options

# Set one-time boot override
client.set_boot_override("Pxe", persistent: false)

# Quick boot methods
client.boot_to_pxe
client.boot_to_disk
client.boot_to_cd
client.boot_to_bios_setup
```

### BIOS Configuration

```ruby
# Get BIOS attributes
attrs = client.bios_attributes

# Set BIOS attribute
client.set_bios_attribute("QuietBoot", "Enabled")

# Reset BIOS to defaults
client.reset_bios_defaults
```

## Configuration Options

- `host`: BMC IP address or hostname
- `username`: BMC username
- `password`: BMC password
- `port`: BMC port (default: 443)
- `use_ssl`: Use HTTPS (default: true)
- `verify_ssl`: Verify SSL certificates (default: false)
- `direct_mode`: Use Basic Auth instead of sessions (default: false)
- `retry_count`: Number of retries for failed requests (default: 3)
- `retry_delay`: Initial delay between retries in seconds (default: 1)

## Debugging

Enable verbose output:

```ruby
client.verbosity = 1  # Basic debug output
client.verbosity = 2  # Include request/response details
client.verbosity = 3  # Include full stack traces
```

## Compatibility

Tested with:
- Supermicro BMC firmware version 01.04.08
- Redfish API version 1.11.0
- Ruby 3.0+

## Differences from iDRAC

While the API is similar to the iDRAC gem, there are some Supermicro-specific differences:

1. **URL Paths**: Supermicro uses numeric IDs (e.g., `/Systems/1`) instead of Dell's embedded names
2. **Redirects**: Supermicro BMC redirects some paths to include trailing slashes
3. **SEL Path**: System Event Log may be at different locations depending on firmware
4. **Task Management**: Task/Job structure differs from Dell's implementation
5. **Virtual Media**: Different action paths and supported media types

## Testing

Run the test script:

```ruby
ruby test_supermicro.rb
```

This will verify:
- Connection and authentication
- Power management functions
- System inventory retrieval
- Storage configuration
- Virtual media operations
- Boot configuration
- Event log access

## License

MIT