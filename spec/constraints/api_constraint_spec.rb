# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApiConstraint do
  it 'matches the request headers to the version' do
    headers = { 'HTTP_ACCEPT' => 'application/vnd.pieforproviders.v1+json' }
    bad_headers = { 'HTTP_ACCEPT' => 'application/vnd.pieforproviders.v11+json' }
    request = ActionDispatch::TestRequest.create(headers)
    bad_request = ActionDispatch::TestRequest.create(bad_headers)
    expect(described_class.new(version: 1, default: true).matches?(request)).to be(true)
    expect(described_class.new(version: 1, default: true).matches?(bad_request)).to be(false)
  end
end
