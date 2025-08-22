# frozen_string_literal: true

module Supermicro
  class Error < StandardError; end
  class AuthenticationError < Error; end
  class ConnectionError < Error; end
  class NotFoundError < Error; end
  class TimeoutError < Error; end
  class BadRequestError < Error; end
end