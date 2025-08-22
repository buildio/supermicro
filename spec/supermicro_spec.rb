require 'spec_helper'

RSpec.describe Supermicro do
  it "has a version number" do
    expect(Supermicro::VERSION).not_to be nil
  end

  describe Supermicro::Client do
    let(:client) do
      described_class.new(
        host: '192.168.1.100',
        username: 'admin',
        password: 'password',
        verify_ssl: false
      )
    end

    it "creates a client instance" do
      expect(client).to be_a(Supermicro::Client)
    end

    it "has a base_url" do
      expect(client.base_url).to eq('https://192.168.1.100')
    end
  end
end