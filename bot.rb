require 'sinatra/base'
require 'slack-ruby-client'
require 'pry'


# This class contains all of the webserver logic for processing incoming requests from Slack.
class API < Sinatra::Base
  # This is the endpoint Slack will post Event data to.
  post '/events' do
    # Extract the Event payload from the request and parse the JSON
    request_data = JSON.parse(request.body.read)
    # Check the verification token provided with the request to make sure it matches the verification token in
    # your app's setting to confirm that the request came from Slack.
    unless SLACK_CONFIG[:slack_verification_token] == request_data['token']
      halt 403, "Invalid Slack verification token received: #{request_data['token']}"
    end

    case request_data['type']
      # When you enter your Events webhook URL into your app's Event Subscription settings, Slack verifies the
      # URL's authenticity by sending a challenge token to your endpoint, expecting your app to echo it back.
      # More info: https://api.slack.com/events/url_verification
      when 'url_verification'
        request_data['challenge']

      when 'event_callback'
        # Get the Team ID and Event data from the request object
        team_id = request_data['team_id']
        event_data = request_data['event']

        # Events have a "type" attribute included in their payload, allowing you to handle different
        # Event payloads as needed.
        case event_data['type']
          when 'message'
            # Event handler for messages, including Share Message actions
            Events.send_task(team_id, event_data)
          else
            # In the event we receive an event we didn't expect, we'll log it and move on.
            puts "Unexpected event:\n"
            puts JSON.pretty_generate(request_data)
        end
        # Return HTTP status code 200 so Slack knows we've received the Event
        status 200
    end
  end

  post '/actions' do
    request_payload = request.env['rack.request.form_hash']['payload']
    request_data = JSON.parse(request_payload)
    Actions.respond(request_data)
    status 200
  end

  post '/tutorial' do
    request_data = request.env['rack.request.form_hash']
    Actions.send_tutorial(request_data)
    status 200
  end
end

# This class contains all of the Event handling logic.
class Events

  def self.parseMessage(message)
    id_spans = []
    current_span = []
    message.chars.each_with_index do |ch, i|
      if ch == '<'
        current_span << i
      elsif ch == '>'
        current_span << i
        id_spans << current_span
        current_span = []
      end
    end

    commands = []
    id_spans.each_with_index do |span, i|
      id = message[span[0]+1...span[1]]
      id = id[1..-1] if id[0] == "@"

      end_idx = id_spans[i+1] ? id_spans[i+1][0] : message.length
      command = message[span[1]+1...end_idx]
      command = command[1..-1] if command[0] == " "
      commands << {id: id, command: command}
    end
    return commands
  end

  def self.send_task(team_id, event_data)
    user_id = event_data['user']
    # Don't process messages sent from our bot user
    unless user_id == $teams[team_id][:bot_user_id]

      # USER SENDS DM TO BOT THAT @S A USER
      if event_data['text'] && event_data['text'].chars.include?("<")
        commands = Events.parseMessage(event_data['text'])
        commands.each do |command|
          $teams[team_id]['client'].chat_postMessage(
            as_user: 'true',
            channel: command[:id],
            attachments: [
              {
                color: "#3c0783",
                title: "New Task!",
                text: "Hello <@#{command[:id]}>,\n<@#{user_id}> has requested the following:\n\n'#{command[:command]}'\n\nClick below when task is complete.",
                callback_id: event_data['channel'],
                attachment_type: "default",
                actions: [
                  {
                    name: "option",
                    value: "completed",
                    text: ":white_large_square: Complete?",
                    type: "button"
                  }
                ]
              }
            ]
          )
        end
      end
    end
  end

end

class Actions
  def self.respond(data)

    unless data["callback_id"] == "disabled"

      team_id = data["team"]["id"]
      
      #SEND OUT RESPONSE MESSAGE
      $teams[team_id]['client'].chat_postMessage(
        as_user: 'true',
        channel: data["callback_id"],
        attachments: [
          {
            color: "#3c0783",
            title: "Task Completed!",
            text: "<@#{data["user"]["id"]}> has completed your task!",
            callback_id: "task completed",
            attachment_type: "default",
          }
        ]
      )

      #UPDATE OLD MESSAGE
      $teams[team_id]['client'].chat_update(
        token: data["token"],
        channel: data["channel"]["id"],
        ts: data["original_message"]["ts"],
        attachments: [
          {
            color: "#3c0783",
            title: "Completed Task.",
            callback_id: "disabled",
            text: data["original_message"]["attachments"][0]["text"],
            attachment_type: "default",
            actions: [
              {
                name: "option",
                value: "completed",
                text: ":white_check_mark: Completed",
                type: "button"
              }
            ]
          }
        ]
      )
    end
  end

  def self.send_tutorial(data)
    team_id = data["team_id"]
    channel = $teams[team_id]['client'].im_open(user: data["user_id"])

    $teams[team_id]['client'].chat_postMessage(
      as_user: 'false',
      channel: channel.channel.id,
      attachments: [
        {
          color: "#3c0783",
          title: "Tutorial",
          text: "Welcome to DonutBot! DonutBot is a helper app for assigning tasks to other users.\n\nTo assign a task, simply send a direct message to DonutBot. In the body of the message, tag the user you'd like to assign the task to followed by the task description in plain text.\n\nYou can include as many tasks to as many users as you like, simply add another tag and task after the first.\nExample: '@Will Take out the trash. @Molly Do the dishes.'",
          callback_id: "tutorial",
          attachment_type: "default",
        }
      ]
    )
  end
end
