require "pathname"
require "net/http"
require "uri"

require "sinatra"

module MailCatcher
  class Web < Sinatra::Base
    set :prefix, "/"
    set :asset_prefix, File.join(prefix, "assets")
    set :root, File.expand_path("#{__FILE__}/../../..")

    def initialize(mail: MailCatcher::Mail.new)
      super()

      @mail = mail
    end

    helpers do
      def asset_path(filename)
        File.join(settings.asset_prefix, filename)
      end
    end

    get "/" do
      erb :index
    end

    delete "/" do
      if MailCatcher.quittable?
        MailCatcher.quit!
        status 204
      else
        status 403
      end
    end

    get "/messages" do
      content_type :json
      JSON.generate(@mail.messages)
    end

    delete "/messages" do
      @mail.delete!
      status 204
    end

    get "/messages/:id.json" do
      id = params[:id].to_i
      if message = @mail.message(id)
        content_type :json
        JSON.generate(message.merge({
          "formats" => [
            "source",
            ("html" if @mail.message_has_html? id),
            ("plain" if @mail.message_has_plain? id)
          ].compact,
          "attachments" => @mail.message_attachments(id).map do |attachment|
            attachment.merge({"href" => "/messages/#{escape(id)}/parts/#{escape(attachment["cid"])}"})
          end,
        }))
      else
        not_found
      end
    end

    get "/messages/:id.html" do
      id = params[:id].to_i
      if part = @mail.message_part_html(id)
        content_type :html, :charset => (part["charset"] || "utf8")

        body = part["body"]

        # Rewrite body to link to embedded attachments served by cid
        body.gsub! /cid:([^'"> ]+)/, "#{id}/parts/\\1"

        body
      else
        not_found
      end
    end

    get "/messages/:id.plain" do
      id = params[:id].to_i
      if part = @mail.message_part_plain(id)
        content_type part["type"], :charset => (part["charset"] || "utf8")
        part["body"]
      else
        not_found
      end
    end

    get "/messages/:id.source" do
      id = params[:id].to_i
      if message = @mail.message(id)
        content_type "text/plain"
        message["source"]
      else
        not_found
      end
    end

    get "/messages/:id.eml" do
      id = params[:id].to_i
      if message = @mail.message(id)
        content_type "message/rfc822"
        message["source"]
      else
        not_found
      end
    end

    get "/messages/:id/parts/:cid" do
      id = params[:id].to_i
      if part = @mail.message_part_cid(id, params[:cid])
        content_type part["type"], :charset => (part["charset"] || "utf8")
        attachment part["filename"] if part["is_attachment"] == 1
        body part["body"].to_s
      else
        not_found
      end
    end

    delete "/messages/:id" do
      id = params[:id].to_i
      if @mail.message(id)
        @mail.delete_message!(id)
        status 204
      else
        not_found
      end
    end

    not_found do
      erb :"404"
    end
  end
end
