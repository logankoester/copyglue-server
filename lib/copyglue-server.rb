require 'date'
require 'json'
require 'rubygems'
require 'c2dm'
require 'pusher'
require 'sinatra'
require 'sinatra/mongomapper'

set :mongomapper, ENV['MONGOMAPPER']
set :mongo_logfile, ENV['MONGO_LOG']

Pusher.app_id = ENV['PUSHER_APP']
Pusher.key = ENV['PUSHER_KEY']
Pusher.secret = ENV['PUSHER_SECRET']

class User
  include MongoMapper::Document

  def self.generate_api_key
    key = (0...8).map{65.+(rand(25)).chr}.join.downcase
    self.generate_api_key if User.find_by_api_key(key)
    key
  end

  key :_id, String
  key :api_key, String, :required => true, :default => self.generate_api_key
  key :c2dm, String
  many :clips

end

class Clip
  include MongoMapper::EmbeddedDocument
  key :text, String, :required => true
  key :source, String, :required => true
  key :timestamp, DateTime, :required => true, :default => DateTime.now
end

class CopyGlueServer < Sinatra::Application
  # Update a user's clipboard
  post '/users/:api_key/clips' do
    if user = User.find_by_api_key(params[:api_key])
      clip = Clip.new(:text => params[:text], 
                  :source => params[:source]
      )
      user.clips << clip
      user.save

      if clip.source == "ANDROID"
        # Notify the Desktop
        pusher_channel = user.api_key + '-' + clip.source
        Pusher[pusher_channel].trigger('new_clips', clip)
      elsif clip.source == "DESKTOP"
        # Notify the Android
      end

      halt 200
    else
      halt 404
    end
  end

  # Register a new account by generating an API key
  post '/users/create' do
    puts "Registering a new user"
    user = User.create
    user.api_key
  end

  # Update a user's C2DM RegistrationId.
  # This happens when the mobile service is launched.
  post '/users/:api_key/c2dm' do
    puts params[:api_key]
    puts 'REGID' + params[:registration_id]
    if user = User.find_by_api_key(params[:api_key])
      user.c2dm = params[:registration_id]
      user.save
      halt 200
    else
      halt 404
    end
  end

  get '/users/:api_key/clips' do
    if user = User.find_by_api_key(params[:api_key])
      user.clips.to_json
    else
      halt 404
    end
  end
end
