require 'json'
require 'active_support/all'
module Lita
  module Handlers
    class Meet < Handler
      config :name_of_auth_group, type: Symbol, default: :standup_participants, required: true
      config :time_to_respond, types: [Integer], default: 60*60 # 60 minutes in seconds
      config :nag_frequency, types: [Integer], default: 15*60 # 15 minutes in seconds
      config :api_key, type: String, default: 'qArnqfhXFb3DWMYtOXuKxjG3iLGHYXHxKnZurDbFAQx2T0zsnm8DrQSYBQep6Njo'
      config :enable_http
      config :standup_message, type: String, default: "Please tell me what you did yesterday, 1. what you're doing today 2. what did you do yesterday 3. something fun. Please prepend your answer with 'standup response'", required: true


      # handler bot routes
      route(/start standup$/, :start_standup, command: true, help: {"start standup" => "triggers a standup"})
      route(/standup response (1.*)(2.*)(3.*)/, :store_response, command: true, help: {"standup response" => "record list of 1. 2. 3. items and replay in room"})
      route(/^standup play$/, :update_room, command: true, help: {"standup play" => "plays all the responses recieved" })
      route(/^standup playback (\d{4})(\d{2})(\d{2})$/, :playback, command: true, help: {"standup playback date" => "plays back a standup from a given date. Date must be in yyyymmdd format"})

      # Http routes
      http.get "/startstandup/:key", :trigger_standup
      http.get "/standups/:key/:date", :fetch_standup

      # START http route commands
      def fetch_standup(request, response)
        if config.enable_http == 'on'
          if request.env["router.params"][:key] == config.api_key
            json_output = {}
            response_prefix = request.env["router.params"][:date]
            json_output["standup-date"] = response_prefix
            redis.keys.each do |key|
              if key.to_s.include? response_prefix
                user = key.gsub(Date.parse(response_prefix).strftime('%Y%m%d') + '-', "")
                json_output[user] = JSON.parse(redis.get(key))
              end
            end
            response.headers["Content-Type"] = "application/json"
            response.write(MultiJson.dump(json_output))
          else
            response.write("invalid api key!")
          end
        else
            response.write("Http isn't enabled. Please enable it in the config by put in lita_config.rb, config.handlers.meet.enable_http = true")
        end
      end

      def trigger_standup(request, response)
        if config.enable_http == 'on'
          if request.env["router.params"][:key] == config.api_key
            redis.set('last_standup_started_at', Time.now)
            find_and_create_users
            message_all_users
          else
            response.write("invalid api key!")
          end
        else
          response.write("Http isn't enabled. Please enable it in the config by put in lita_config.rb, config.handlers.meet.enable_http = true")
        end
      end
      # END http route commands

      # START bot methods
      def start_standup(response)
        redis.set('last_standup_started_at', Time.now)
        find_and_create_users
        message_all_users
        nag_users_for_response if config.nag_frequency.present? && config.nag_frequency > 0
      end

      def store_response(response)
        #TODO: add check for the last person to response, trigger a play in the room
        return unless can_respond?
        redis.set(response_key(response.user.name), response.matches.first)
        response.reply('Response recorded. Thanks for partipating')
      end

      def update_room(response)
        room = Source.new(room: response.room)
        message_body = ''
        response_prefix = started_at.strftime('%Y%m%d')
        redis.keys.each do |key|
          if key.to_s.include? response_prefix
            message_body += key.gsub(response_prefix + '-', "")
            message_body += "\n"
            message_body += MultiJson.load(redis.get(key)).join("\n")
            message_body += "\n"
          end
        end
        robot.send_message(room, message_body)
      end

      def playback(response)
        message_body = ''
        playback_param = response.matches.first
        search_date = playback_param[0]+playback_param[1]+playback_param[2]
        message_body += "Playing back standup from #{search_date}: \n\n"
        redis.keys.each do |key|
          if key.to_s.include? search_date
            message_body += key.gsub(Date.parse(search_date).strftime('%Y%m%d') + '-', "")
            message_body += "\n"
            message_body += MultiJson.load(redis.get(key)).join("\n")
            message_body += "\n"
          end
        end
        response.reply_privately(message_body)
      end

      # END bot methods

      private

      def nag_users_for_response
        every(config.nag_frequency) do |timer|
          user_responses = check_completion
          if user_responses[:incomplete].empty? || !can_respond?
            timer.stop
          else
            user_responses[:incomplete].each do |user|
              send_nag(user)
            end
          end
        end
      end

       def check_completion
        result = { complete: [], incomplete: [] }
        @users.each do |user|
          response = redis.get(response_key(user.name))
          if response.present?
            result[:complete] << user
          else
            result[:incomplete] << user
          end
        end
        result
      end

       def send_nag(user)
        source = Lita::Source.new(user: user)
        robot.send_message(source, 'Hate to nag but would for the shake of god.')
        robot.send_message(source, 'Send in your Standup notes using standup response!')
      end

      def message_all_users
        @users.each do |user|
          source = Lita::Source.new(user: user)
          robot.send_message(source, "Time for standup!")
          robot.send_message(source, config.standup_message)
        end
      end

      def response_key(username, timestamp=started_at)
        return timestamp.strftime('%Y%m%d') + "-" + cleanup_username(username)
      end

      def cleanup_username(username)
        username.gsub(' ', '_')
      end

      def find_and_create_users
        @users ||= robot.auth.groups_with_users[config.name_of_auth_group]
      end

      def timing_is_right?
        return false if redis.get('last_standup_started_at').nil?
        intitiated_at = Time.parse(redis.get('last_standup_started_at'))
        Time.now > intitiated_at && intitiated_at + (60*config.time_to_respond) > Time.now
      end

      Lita.register_handler(self)
    end
  end
end
