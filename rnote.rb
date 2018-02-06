require "sinatra"
require "sinatra/content_for"
require "tilt/erubis"

require_relative "lib/database"

configure do
  set :erb, :escape_html => true
  enable :sessions
  set :session_secret, "secret"
end

configure(:development) do
  require "sinatra/reloader"
  also_reload "database.rb"
end

before do
  @storage = Database.new(logger)
  @user_id = 1
end

after do
  @storage.disconnect
end

helpers do

end

# ROUTES ==============================

get "/" do
  erb :folder, layout: :layout
end

get "/folders/new" do
  erb :new_folder, layout: :layout
end

get "/folders/:id" do
  @folder_id = params[:id]
  @folder = @storage.load_folder(@folder_id)

  erb :folder, layout: :layout
end
