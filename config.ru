ENV["RACK_ENV"] ||= "development"

require "rack"
require "rack/contrib"

require 'openssl'
OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE

require './app'

use Rack::PostBodyContentTypeParser

use ExceptionHandling

run App