# Helper module for loading Redfish test fixtures
module RedfishFixtures
  def load_fixture(fixture_name)
    fixture_path = File.join(File.dirname(__FILE__), '..', 'fixtures', 'redfish', "#{fixture_name}.json")
    JSON.parse(File.read(fixture_path))
  end
  
  def mock_redfish_response(fixture_name, status: 200)
    body = load_fixture(fixture_name)
    response = double('Response')
    allow(response).to receive(:status).and_return(status)
    allow(response).to receive(:body).and_return(body.to_json)
    response
  end
end