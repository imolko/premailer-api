require "rubygems"
require "bundler/setup"

Bundler.require(ENV["RACK_ENV"])

require "sinatra/base"
require "sinatra/streaming"
require "sinatra/multi_route"

require "premailer"
require "oj"
require "mail"

# Determina si un string es un uri.
# externo.
def uri?(string)
  uri = URI.parse(string)
  %w( http https ).include?(uri.scheme)
rescue URI::BadURIError
  false
rescue URI::InvalidURIError
  false
end

# Clase Inicial
class App < Sinatra::Base
    register Sinatra::MultiRoute
    helpers  Sinatra::Streaming
    disable :protection

    # configuracion de handle del errores.
    configure do
        # Don't log them. We'll do that ourself
        set :dump_errors, false

        # Don't capture any errors. Throw them up the stack
        set :raise_errors, true

        # Disable internal middleware for presenting errors
        # as useful HTML pages
        set :show_exceptions, false
    end

    # Devolvemos la version
    get '/', '/api' do
        headers "Content-Type" => "application/json"
        Oj.dump({
            "premailer-api" => "Api para premailer y otros relacionados mimes.",
            "version" => "1.0",
            "endpoints" => ["POST /api/1.0/mime", "POST /api/1.0/premailer"],
            "source" => "https://github.com/imolko/premailer-api"
        })
    end

    # Se encarga de recibir el html como venga sin 
    # llamada a premailer.
    post '/api/1.0/mime' do
        url = params["content"]

        headers "Content-Type" => "message/rfc822"
        
        mail = Mail.new do
            to      '{{to}}'
            from    '{{from}}'
            reply   '{{from}}'
            subject "{{iml.subject}}"
        end

        _charset = 'utf-8'
        _content_type = 'text/html; charset=utf-8'
        _content = ''
        _valid_encoding = true

        open(url) { |f|
            _charset = f.charset if f.charset
            _content_type = f.content_type

            f.set_encoding(_charset)
            _content = f.read()

            if not _content.valid_encoding?
                _valid_encoding = false
                _content = _content.scrub
            end
        }

        html_part = Mail::Part.new do
            content_type "#{_content_type}; charset=#{_charset}"
            headers "X-valid-encoding" => "#{_valid_encoding}"
            body  _content
        end

        mail.html_part = html_part

        mail.to_s
    end

    post '/api/1.0/premailer' do
        # Establecemos las opciones
        options = Hash.new
        options[:with_html_string] = false
        options[:include_link_tags] = false
        options[:include_style_tags] = false

        # Leemos los parametros desde el json
        param_options = params["options"];
        if ! param_options.nil?
            param_options.each{ |key, value| options[key.to_sym] = value }
        end

        # Forzamos siempre a utilizar este adaptador.
        options[:adapter] = :nokogiri

        email_contents = params["content"]

        # levantamos un error si se espera un url y no se encuentra.
        raise ArgumentError, 'Argument is not url' unless  options[:with_html_string] || uri(email_contents)

        # llamamos a premailer.
        premailer = Premailer.new(email_contents, options)

        if params["output"] == "html"
            headers "Content-Type" => "text/html"

            # Escribimos los warning como headers.
            premailer.warnings.group_by { |w| w[:level].downcase }.map do |key, wa|
                wa.map do |w|
                    headers "X-warning-#{key}" => "#{w[:message]} may not render properly in #{w[:clients]}"
                end
            end

            premailer.to_inline_css
        elsif params["output"] == "text"
            headers "Content-Type" => "text/plain"

            # Escribimos los warning como headers.
            premailer.warnings.group_by { |w| w[:level].downcase }.map do |key, wa|
                wa.map do |w|
                    headers "X-warning-#{key}" => "#{w[:message]} may not render properly in #{w[:clients]}"
                end
            end

            premailer.to_plain_text
        elsif params["output"] == "mime"
            headers "Content-Type" => "message/rfc822"

            _mail = Mail.new do
                to      '{{to}}'
                from    '{{from}}'
                reply   '{{from}}'
                subject "{{iml.subject}}"
            end

            _text_part = Mail::Part.new do
                content_type 'text/plain; charset=UTF-8'
                body  premailer.to_plain_text
            end

            _html_part = Mail::Part.new do
                content_type 'text/html; charset=UTF-8'
                body  premailer.to_inline_css
            end

            #mail.charset = 'UTF-8'
            _mail.text_part = _text_part
            _mail.html_part = _html_part

            # Escribimos los warning como headers.
            premailer.warnings.group_by { |w| w[:level].downcase }.map do |key, wa|
                wa.map do |w|
                    _mail.header["X-warning-#{key}"] = "#{w[:message]} may not render properly in #{w[:clients]}"
                end
            end

            _mail.to_s
        else
            # Respondemos en json.
            headers "Content-Type" => "application/json"
            Oj.dump({
                "html" => premailer.to_inline_css,
                "text" => premailer.to_plain_text,
                "warnings" => premailer.warnings.group_by { |w| w[:level].downcase }.map do |key, wa|
                [key, wa.map do |w|
                    "#{w[:message]} may not render properly in #{w[:clients]}"
                end]
                end.to_h
            })
        end
    end
end

class ExceptionHandling
  def initialize(app)
    @app = app
  end

  def call(env)
    begin
      @app.call env
    rescue => ex
      env['rack.errors'].puts ex
      env['rack.errors'].puts ex.backtrace.join("\n")
      env['rack.errors'].flush

      hash = { :message => ex.to_s }
      hash[:backtrace] = ex.backtrace 

      #if RACK_ENV['development']
      #  hash[:backtrace] = ex.backtrace 
      #end

      [500, {'Content-Type' => 'application/json'}, [Oj.dump(hash)]]
    end
  end
end

