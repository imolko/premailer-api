ENV["RACK_ENV"] ||= "development"

require "rack"
require "rack/contrib"

require './app'

use Rack::PostBodyContentTypeParser

use ExceptionHandling

run App