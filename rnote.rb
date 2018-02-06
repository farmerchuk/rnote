require "sinatra"
require "sinatra/content_for"
require "tilt/erubis"

require_relative "lib/database_persistence"

configure do
  set :erb, :escape_html => true
  enable :sessions
  set :session_secret, "secret"
end

configure(:development) do
  require "sinatra/reloader"
  also_reload "database_persistence.rb"
end

before do
  #@storage = DatabasePersistence.new(logger)
end

after do
  #@storage.disconnect
end

helpers do

end

# ROUTES ==============================

get "/" do
  erb :folder, layout: :layout
end
