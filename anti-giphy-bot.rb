####
#
#
# Requires
#
#
####

require 'sinatra'
require 'logger'
require 'rest-client'
require 'dotenv'
require 'json'
#require 'sinatra/reloader'
require 'uri'
require 'retries'
require 'ruby-filemagic'
require 'animated_gif_detector'

####
#
#
# Variables and constants
#
#
####

#load .env variables
Dotenv.load

OAUTH_TOKEN = ENV["OAUTH_TOKEN"]
PORT = ENV["PORT"].to_i
LOGFILE = ENV["LOGFILE"]

AUTHORIZATION = "Bearer #{OAUTH_TOKEN}"

RESOURCE = RestClient::Resource.new 'https://api.ciscospark.com/v1', :headers => {:accept => :json, :content_type => :json, :authorization => AUTHORIZATION}

$logger = Logger.new(LOGFILE)

File.open('server.pid', 'w') {|f| f.write Process.pid }

####
#
#
# Classes
#
#
####

class TooManyRequestsError < StandardError
  attr_reader :retry_after
  def initialize(retry_after=1)
    @retry_after = retry_after
    super("Retry after #{@retry_after} seconds")
  end
end

####
#
#
# Functions
#
#
####

def raw_message(message_id)

  too_many_requests = Proc.new do |exception, attempt_number, total_delay|
    sleep exception.retry_after
  end
  
  with_retries(:max_tries => 10, :handler => too_many_requests, :rescue => TooManyRequestsError) do |attempt|
    message = RESOURCE["messages/#{message_id}"].get(:accept => :json, :content_type => :json, :authorization => AUTHORIZATION){|response, request, result| response}
    if (message.code == 200)
      parsed_message = JSON.parse(message)
      return parsed_message
    elsif (message.code == 429)
      $logger.debug("Forced to retry due to 429")
      raise TooManyRequestsError.new(message.headers[:retry_after].to_i)
    else
      $logger.fatal("Failure to read a message:\nMessage ID:\n#{message_id}\nResponse code: #{message.code}\nResponse headers:\n#{message.headers}")
      return {}
    end
  end
end

def test_file_for_gif(file_path)
  filetype = ""
  
  FileMagic.open(:mime) {|fm|
    filetype = fm.file(file_path)
  }
  
  gif = "image/gif; charset=binary"
  
  if(filetype == gif)
    return true
  else
    return false
  end
end

def test_file_for_animated_gif(file_path)
  test_result = AnimatedGifDetector.new(File.open(file_path, 'rb')).animated?
  return test_result
end

def retrieve_file_head(file_id)
  too_many_requests = Proc.new do |exception, attempt_number, total_delay|
    sleep exception.retry_after
  end
  
  with_retries(:max_tries => 10, :handler => too_many_requests, :rescue => TooManyRequestsError) do |attempt|
    file = RESOURCE["contents/#{file_id}"].head(:accept => :json, :content_type => :json, :authorization => AUTHORIZATION){|response, request, result| response}
    if (file.code == 200)
      $logger.debug("retrieved HEAD of file ID: #{file_id}")
      return file
    elsif (file.code == 429)
      $logger.debug("Forced to retry due to 429")
      raise TooManyRequestsError.new(file.headers[:retry_after].to_i)
    else
      $logger.fatal("Failure to retrieve file HEAD:\nFile ID:\n#{file_id}\nResponse code: #{file.code}\nResponse headers:\n#{file.headers}")
      return {}
    end
  end
  
end

def retrieve_file(file_id)
  too_many_requests = Proc.new do |exception, attempt_number, total_delay|
    sleep exception.retry_after
  end
  
  with_retries(:max_tries => 10, :handler => too_many_requests, :rescue => TooManyRequestsError) do |attempt|
    file = RESOURCE["contents/#{file_id}"].get(:accept => :json, :content_type => :json, :authorization => AUTHORIZATION){|response, request, result| response}
    if (file.code == 200)
      $logger.debug("retrieved file ID: #{file_id}")
      return file
    elsif (file.code == 429)
      $logger.debug("Forced to retry due to 429")
      raise TooManyRequestsError.new(file.headers[:retry_after].to_i)
    else
      $logger.fatal("Failure to delete a message:\nMessage ID:\n#{file_id}\nResponse code: #{file.code}\nResponse headers:\n#{file.headers}")
      return {}
    end
  end
  
end

def delete_message(message_id)
  too_many_requests = Proc.new do |exception, attempt_number, total_delay|
    sleep exception.retry_after
  end
  
  with_retries(:max_tries => 10, :handler => too_many_requests, :rescue => TooManyRequestsError) do |attempt|
    message = RESOURCE["messages/#{message_id}"].delete(:accept => :json, :content_type => :json, :authorization => AUTHORIZATION){|response, request, result| response}
    if (message.code == 204)
      $logger.debug("Deleted message ID: #{message_id}")
      return true
    elsif (message.code == 429)
      $logger.debug("Forced to retry due to 429")
      raise TooManyRequestsError.new(message.headers[:retry_after].to_i)
    else
      $logger.fatal("Failure to delete a message:\nMessage ID:\n#{message_id}\nResponse code: #{message.code}\nResponse headers:\n#{message.headers}")
      return false
    end
  end
  
end

def post_room_text_message(room_id, text)
  message = {"roomId" => room_id, "text" => text}
  json_message = message.to_json
  str_message = json_message.to_s
  
  too_many_requests = Proc.new do |exception, attempt_number, total_delay|
    sleep exception.retry_after
  end
  
  with_retries(:max_tries => 10, :handler => too_many_requests, :rescue => TooManyRequestsError) do |attempt|
    result = RESOURCE["messages"].post(str_message, {:accept => :json, :content_type => "application/json; charset=UTF-8", :authorization => AUTHORIZATION}){|response, request, result| response}
    if (result.code == 200)
      return true
    elsif (result.code == 429)
      $logger.debug("Forced to retry due to 429")
      raise TooManyRequestsError.new(result.headers[:retry_after].to_i)
    else
      $logger.fatal("Failure to post a message:\nRoom ID:\n#{room_id}\nMessage:\n#{message}\nMessage JSON:\n#{JSON.pretty_generate(message)}\nResponse code: #{result.code}\nResponse headers:\n#{result.headers}")
      return false
    end
  end
end

####
#
#
# Program
#
#
####

set :port, PORT

post '/' do

  payload = JSON.parse(request.body.read)
  
  $logger.debug("payload = #{payload.inspect}")
  
  if((payload["resource"] == "messages") && (payload["event"] == "created"))
    $logger.debug("we have a new message to process")
    
    message_id = payload["data"]["id"]
    
    #raw_message = raw_message(message_id)
    
    #$logger.debug("message is #{raw_message.inspect}")
    
    if payload["data"].has_key?("files")
      number_of_files = payload["data"]["files"].length
    else
      number_of_files = 0
    end
    
    $logger.debug("detected #{number_of_files} files")
    
    if(number_of_files > 0)
      $logger.debug("testing #{number_of_files} files")
      #iterate over files
      animated_files_present = false
      #test each file to see if it is a GIF
      payload["data"]["files"].each do |url|
        $logger.debug("testing file \"#{url}\"")
        #parse URL
        uri = URI(url)
        #determine path - method excludes any query variables, anchors, etc.
        path = uri.path
        #parse just the filename from the overall path
        file_id = File.basename(path)

        #download the HEAD and check content-type
        $logger.debug("testing file \"#{url}\" via HEAD check")
        file_head = retrieve_file_head(file_id)
        file_headers = file_head.headers
        
        #if it is a GIF, download it and test if it is an animated GIF
        if(file_headers[:content_type] == "image/gif")
          $logger.debug("file \"#{url}\" is a gif according to HEAD")
          #download the file, direct use of "url" is perhaps not totally safe...
          temp_file_path = "/tmp/#{file_id}"
          file = File.open(temp_file_path, 'wb' ) do |output|
            output.write retrieve_file(file_id)
          end
          #test file, true == animated gif
          if(test_file_for_gif(temp_file_path))
            $logger.debug("file \"#{url}\" is a gif according to filemagic (mime)")
            if(test_file_for_animated_gif(temp_file_path))
              $logger.debug("file \"#{url}\" is an animated gif according to animated gif tester")
              animated_files_present = true
            else
              $logger.debug("file \"#{url}\" is NOT an animated gif according to animated gif tester")
            end
          else
            $logger.debug("file \"#{url}\" is NOT a gif according to filemagic (mime).  Spark lied to us!")
          end
        else
          $logger.debug("file \"#{url}\" is NOT a gif according to HEAD")
        end
      end
      #if necessary, delete the file
      if(animated_files_present)
        $logger.debug("proceeding with deletion of message #{message_id}")
        if delete_message(message_id)
          $logger.debug("deleted message id: #{message_id}")
          room_id = payload["data"]["roomId"]
          message_text = '¯\\_(ツ)_/¯ Most regretfully, I have been instructed to clear this room of animated GIFs.'
          post_room_text_message(room_id, message_text)
          return 201
        else
          $logger.debug("failed to delete message id: #{message_id}")
          return 500
        end
        
      else
        $logger.debug("message with no animated gifs, no action taken")
        return 204
      end
    else
      $logger.debug("message with no files, no action taken")
      return 204
    end
  else
    $logger.debug("unknown webhook data.  payload = #{payload.to_s}")
    return 204
  end
end
