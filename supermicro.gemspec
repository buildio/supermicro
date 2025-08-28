# frozen_string_literal: true

require_relative "lib/supermicro/version"

Gem::Specification.new do |spec|
  spec.name = "supermicro"
  spec.version = Supermicro::VERSION
  spec.authors = ["Jonathan Siegel"]
  spec.email = ["248302+usiegj00@users.noreply.github.com"]

  spec.summary = "API Client for Supermicro BMC"
  spec.description = "A Ruby client for the Supermicro BMC Redfish API with support for power management, virtual media, and system configuration"
  spec.homepage = "https://github.com/buildio/supermicro"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/buildio/supermicro"
  spec.metadata["changelog_uri"] = "https://github.com/buildio/supermicro/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{lib}/**/*", "LICENSE", "README.md", "*.gemspec"]
  end

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "httparty", "~> 0.21"
  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "faraday-multipart", "~> 1.0"
  spec.add_dependency "nokogiri", "~> 1.14"
  spec.add_dependency "colorize", ">= 0.8"
  spec.add_dependency "activesupport", ">= 7.0"
  
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "webmock", "~> 3.0"
  spec.add_development_dependency "debug", "~> 1.0"
end