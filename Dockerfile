FROM ruby:2.4.1-alpine

# Establecemos a utf-8
ENV LANG C.UTF-8

# Creamos la ruta para la aplicacion.
RUN mkdir -p /usr/src/app

# Directorio por defecto
WORKDIR /usr/src/app

COPY Gemfile /usr/src/app
COPY Gemfile.lock /usr/src/app

# Ejecutamos la compilacion.
RUN bundle install --without development

# Exponemos el puerto 80
EXPOSE 80

CMD ["bundle", "exec", "rackup", "--server", "puma", "--host", "0.0.0.0", "--port", "80"]

# Añadimos todos los archivos a la aplicacion
ADD . /usr/src/app