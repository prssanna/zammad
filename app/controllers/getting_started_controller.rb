# Copyright (C) 2012-2014 Zammad Foundation, http://zammad-foundation.org/

require 'resolv'

class GettingStartedController < ApplicationController

=begin

Resource:
GET /api/v1/getting_started

Response:
{
  "master_user": 1,
  "groups": [
    {
      "name": "group1",
      "active":true
    },
    {
      "name": "group2",
      "active":true
    }
  ]
}

Test:
curl http://localhost/api/v1/getting_started -v -u #{login}:#{password}

=end

  def index

    # check if first user already exists
    return if setup_done_response

    # if master user already exists, we need to be authenticated
    if setup_done
      return if !authentication_check
    end

    # get all groups
    groups = Group.where( :active => true )

    # return result
    render :json => {
      :setup_done     => setup_done,
      :import_mode    => Setting.get('import_mode'),
      :import_backend => Setting.get('import_backend'),
      :groups         => groups,
    }
  end

  def base

    # check admin permissions
    return if deny_if_not_role('Admin')

    # validate url
    messages = {}
    if !params[:url] ||params[:url] !~ /^(http|https):\/\/.+?$/
      messages[:url] = 'A URL looks like http://zammad.example.com'
    end

    # validate organization
    if !params[:organization] || params[:organization].empty?
      messages[:organization] = 'Invalid!'
    end

    # validate image
    if params[:logo] && !params[:logo].empty?
      content_type = nil
      content      = nil

      # data:image/png;base64
      if params[:logo] =~ /^data:(.+?);base64,(.+?)$/
        content_type = $1
        content      = $2
      end

      if !content_type || !content
        messages[:logo] = 'Unable to process image upload.'
      end
    end

    if !messages.empty?
      render :json => {
        :result   => 'invalid',
        :messages => messages,
      }
      return
    end

    # split url in http_type and fqdn
    settings = {}
    if params[:url] =~ /^(http|https):\/\/(.+?)$/
      Setting.set('http_type', $1)
      settings[:http_type] = $1
      Setting.set('fqdn', $2)
      settings[:fqdn] = $2
    end

    # save organization
    Setting.set('organization', params[:organization])
    settings[:organization] = params[:organization]

    # save image
    if params[:logo] && !params[:logo].empty?
      content_type = nil
      content      = nil

      # data:image/png;base64
      if params[:logo] =~ /^data:(.+?);base64,(.+?)$/
        content_type = $1
        content      = Base64.decode64($2)
      end
      Store.remove( :object => 'System::Logo', :o_id => 1 )
      Store.add(
        :object      => 'System::Logo',
        :o_id        => 1,
        :data        => content,
        :filename    => 'image',
        :preferences => {
          'Content-Type' => content_type
        },
#        :created_by_id => self.updated_by_id,
      )
    end

    render :json => {
      :result   => 'ok',
      :settings => settings,
    }
  end

  def email_probe

    # check admin permissions
    return if deny_if_not_role('Admin')

    # validation
    user   = nil
    domain = nil
    if params[:email] =~ /^(.+?)@(.+?)$/
      user   = $1
      domain = $2
    end

    if !user || !domain
      render :json => {
        :result   => 'invalid',
        :messages => {
          :email => 'Invalid email.'
        },
      }
      return
    end

    # check domain based attributes
    providerMap = {
      :google => {
        :domain => 'gmail.com|googlemail.com|gmail.de',
        :inbound => {
          :adapter => 'imap',
          :options => {
            :host     => 'imap.gmail.com',
            :port     => '993',
            :ssl      => true,
            :user     => params[:email],
            :password => params[:password],
          },
        },
        :outbound => {
          :adapter => 'smtp',
          :options => {
            :host     => 'smtp.gmail.com',
            :port     => '465',
            :ssl      => true,
            :user     => params[:email],
            :password => params[:password],
          }
        },
      },
    }

    # probe based on email domain and mx
    domains = [domain]
    mail_exchangers = mxers(domain)
    if mail_exchangers && mail_exchangers[0]
      puts "MX #{mail_exchangers} - #{mail_exchangers[0][0]}"
    end
    if mail_exchangers && mail_exchangers[0] && mail_exchangers[0][0]
      domains.push mail_exchangers[0][0]
    end
    providerMap.each {|provider, settings|
      domains.each {|domain_to_check|
        if domain_to_check =~ /#{settings[:domain]}/i

          # probe inbound
          result = email_probe_inbound( settings[:inbound] )
          if !result
            render :json => result
            return
          end

          # probe outbound
          result = email_probe_outbound( settings[:outbound], params[:email] )
          if result[:result] != 'ok'
            render :json => result
            return
          end

          render :json => {
            :result  => 'ok',
            :account => settings,
          }
          return
        end
      }
    }

    # probe inbound
    inboundMap = []
    if mail_exchangers && mail_exchangers[0] && mail_exchangers[0][0]
      inboundMx = [
        {
          :adapter => 'imap',
          :options => {
            :host     => mail_exchangers[0][0],
            :port     => 993,
            :ssl      => true,
            :user     => user,
            :password => params[:password],
          },
        },
        {
          :adapter => 'imap',
          :options => {
            :host     => mail_exchangers[0][0],
            :port     => 993,
            :ssl      => true,
            :user     => params[:email],
            :password => params[:password],
          },
        },
      ]
      inboundMap = inboundMap + inboundMx
    end
    inboundAuto = [
      {
        :adapter => 'imap',
        :options => {
          :host     => "mail.#{domain}",
          :port     => 993,
          :ssl      => true,
          :user     => user,
          :password => params[:password],
        },
      },
      {
        :adapter => 'imap',
        :options => {
          :host     => "mail.#{domain}",
          :port     => 993,
          :ssl      => true,
          :user     => params[:email],
          :password => params[:password],
        },
      },
      {
        :adapter => 'imap',
        :options => {
          :host     => "imap.#{domain}",
          :port     => 993,
          :ssl      => true,
          :user     => user,
          :password => params[:password],
        },
      },
      {
        :adapter => 'imap',
        :options => {
          :host     => "imap.#{domain}",
          :port     => 993,
          :ssl      => true,
          :user     => params[:email],
          :password => params[:password],
        },
      },
      {
        :adapter => 'pop3',
        :options => {
          :host     => "mail.#{domain}",
          :port     => 995,
          :ssl      => true,
          :user     => user,
          :password => params[:password],
        },
      },
      {
        :adapter => 'pop3',
        :options => {
          :host     => "mail.#{domain}",
          :port     => 995,
          :ssl      => true,
          :user     => params[:email],
          :password => params[:password],
        },
      },
      {
        :adapter => 'pop3',
        :options => {
          :host     => "pop.#{domain}",
          :port     => 995,
          :ssl      => true,
          :user     => user,
          :password => params[:password],
        },
      },
      {
        :adapter => 'pop3',
        :options => {
          :host     => "pop.#{domain}",
          :port     => 995,
          :ssl      => true,
          :user     => params[:email],
          :password => params[:password],
        },
      },
      {
        :adapter => 'pop3',
        :options => {
          :host     => "pop3.#{domain}",
          :port     => 995,
          :ssl      => true,
          :user     => user,
          :password => params[:password],
        },
      },
      {
        :adapter => 'pop3',
        :options => {
          :host     => "pop3.#{domain}",
          :port     => 995,
          :ssl      => true,
          :user     => params[:email],
          :password => params[:password],
        },
      },
    ]
    inboundMap = inboundMap + inboundAuto
    settings = {}
    success = false
    inboundMap.each {|config|
      puts "PROBE: #{config.inspect}"
      result = email_probe_inbound( config )
      puts "RESULT: #{result.inspect}"
      if !result
        success = true
        settings[:inbound] = config
        break
      end
    }

    if !success
      render :json => {
        :result => 'failed',
      }
      return
    end

    # probe outbound
    outboundMap = []
    if mail_exchangers && mail_exchangers[0] && mail_exchangers[0][0]
      outboundMx = [
        {
          :adapter => 'smtp',
          :options => {
            :host     => mail_exchangers[0][0],
            :port     => 25,
            :ssl      => true,
            :user     => user,
            :password => params[:password],
          },
        },
        {
          :adapter => 'smtp',
          :options => {
            :host     => mail_exchangers[0][0],
            :port     => 25,
            :ssl      => true,
            :user     => params[:email],
            :password => params[:password],
          },
        },
        {
          :adapter => 'smtp',
          :options => {
            :host     => mail_exchangers[0][0],
            :port     => 465,
            :ssl      => true,
            :user     => user,
            :password => params[:password],
          },
        },
        {
          :adapter => 'smtp',
          :options => {
            :host     => mail_exchangers[0][0],
            :port     => 465,
            :ssl      => true,
            :user     => params[:email],
            :password => params[:password],
          },
        },
      ]
      outboundMap = outboundMap + outboundMx
    end
    outboundAuto = [
      {
        :adapter => 'smtp',
        :options => {
          :host     => "mail.#{domain}",
          :port     => 25,
          :ssl      => true,
          :user     => user,
          :password => params[:password],
        },
      },
      {
        :adapter => 'smtp',
        :options => {
          :host     => "mail.#{domain}",
          :port     => 25,
          :ssl      => true,
          :user     => params[:email],
          :password => params[:password],
        },
      },
      {
        :adapter => 'smtp',
        :options => {
          :host     => "mail.#{domain}",
          :port     => 465,
          :ssl      => true,
          :user     => user,
          :password => params[:password],
        },
      },
      {
        :adapter => 'smtp',
        :options => {
          :host     => "mail.#{domain}",
          :port     => 465,
          :ssl      => true,
          :user     => params[:email],
          :password => params[:password],
        },
      },
      {
        :adapter => 'smtp',
        :options => {
          :host     => "smtp.#{domain}",
          :port     => 25,
          :ssl      => true,
          :user     => user,
          :password => params[:password],
        },
      },
      {
        :adapter => 'smtp',
        :options => {
          :host     => "smtp.#{domain}",
          :port     => 25,
          :ssl      => true,
          :user     => params[:email],
          :password => params[:password],
        },
      },
      {
        :adapter => 'smtp',
        :options => {
          :host     => "smtp.#{domain}",
          :port     => 465,
          :ssl      => true,
          :user     => user,
          :password => params[:password],
        },
      },
      {
        :adapter => 'smtp',
        :options => {
          :host     => "smtp.#{domain}",
          :port     => 465,
          :ssl      => true,
          :user     => params[:email],
          :password => params[:password],
        },
      },
    ]

    success = false
    outboundMap.each {|config|
      puts "PROBE: #{config.inspect}"
      result = email_probe_outbound( config, params[:email] )
      puts "RESULT: #{result.inspect}"
      if result[:result] == 'ok'
        success = true
        settings[:outbound] = config
        break
      end
    }

    if !success
      render :json => {
        :result => 'failed',
      }
      return
    end

    render :json => {
      :result  => 'ok',
      :setting => settings,
    }
  end

  def email_outbound

    # check admin permissions
    return if deny_if_not_role('Admin')

    # validate params
    if !params[:adapter]
      render :json => {
        :result => 'invalid',
      }
      return
    end

    # connection test
    result = email_probe_outbound( params, params[:email] )
    if result[:result] != 'ok'
      render :json => result
      return
    end

    # return result
    render :json => {
      :result => 'ok',
    }
  end

  def email_inbound

    # check admin permissions
    return if deny_if_not_role('Admin')

    # validate params
    if !params[:adapter]
      render :json => {
        :result => 'invalid',
      }
      return
    end

    # connection test
    result = email_probe_inbound( params )
    if result
      render :json => result
      return
    end

    render :json => {
      :result => 'ok',
    }
  end

  def email_verify

    # check admin permissions
    return if deny_if_not_role('Admin')

    # send verify email to inbox
    subject = '#' + rand(99999999999).to_s
    Channel::EmailSend.new.send(
      {
        :from             => params[:meta][:email],
        :to               => params[:meta][:email],
        :subject          => "Zammad Getting started Test Email #{subject}",
        :body             => '.',
        'x-zammad-ignore' => 'true',
      }
    )
    (1..5).each {|loop|
      sleep 10

      # fetch mailbox
      found = nil
      if params[:inbound][:adapter] =~ /^imap$/i
        found = Channel::IMAP.new.fetch( { :options => params[:inbound][:options] }, 'verify', subject )
      else
        found = Channel::POP3.new.fetch( { :options => params[:inbound][:options] }, 'verify', subject )
      end

      if found && found == 'verify ok'

        # remember address
        address = EmailAddress.all.first
        if address
          address.update_attributes(
            :realname      => params[:meta][:realname],
            :email         => params[:meta][:email],
            :active        => 1,
            :updated_by_id => 1,
            :created_by_id => 1,
          )
        else
          EmailAddress.create(
            :realname      => params[:meta][:realname],
            :email         => params[:meta][:email],
            :active        => 1,
            :updated_by_id => 1,
            :created_by_id => 1,
          )
        end

        # store mailbox
        Channel.create(
          :area          => 'Email::Inbound',
          :adapter       => params[:inbound][:adapter],
          :options       => params[:inbound][:options],
          :group_id      => 1,
          :active        => 1,
          :updated_by_id => 1,
          :created_by_id => 1,
        )

        # save settings
        if params[:outbound][:adapter] =~ /^smtp$/i
          smtp = Channel.where( :adapter  => 'SMTP', :area => 'Email::Outbound' ).first
          smtp.options = params[:outbound][:options]
          smtp.active  = true
          smtp.save!
          sendmail = Channel.where( :adapter => 'Sendmail' ).first
          sendmail.active = false
          sendmail.save!
        else
          sendmail = Channel.where( :adapter => 'Sendmail', :area => 'Email::Outbound' ).first
          sendmail.options = {}
          sendmail.active  = true
          sendmail.save!
          smtp = Channel.where( :adapter => 'SMTP' ).first
          smtp.active = false
          smtp.save
        end

        render :json => {
          :result => 'ok',
        }
        return
      end
    }

    # check dilivery for 30 sek.
    render :json => {
      :result  => 'invalid',
      :message => 'Verification Email not found in mailbox.',
    }
  end

  private

  def email_probe_outbound(params, email)

    # validate params
    if !params[:adapter]
      result = {
        :result  => 'invalid',
        :message => 'Invalid!',
      }
      return result
    end

    # test connection
    translationMap = {
      'authentication failed' => 'Authentication failed!',
      'getaddrinfo: nodename nor servname provided, or not known' => 'Hostname not found!',
      'No route to host' => 'No route to host!',
      'Connection refused' => 'Connection refused!',
    }
    if params[:adapter] == 'smtp'
      begin
        Channel::SMTP.new.send(
          {
            :from    => email,
            :to      => 'emailtrytest@znuny.com',
            :subject => 'test',
            :body    => 'test',
          },
          {
            :options => params[:options]
          }
        )
      rescue Exception => e

        # check if sending email was ok, but mailserver rejected
        whiteMap = {
          'Recipient address rejected' => true,
        }
        whiteMap.each {|key, message|
          if e.message =~ /#{Regexp.escape(key)}/i
            result = {
              :result => 'ok',
            }
            return result
          end
        }
        message_human = ''
        translationMap.each {|key, message|
          if e.message =~ /#{Regexp.escape(key)}/i
            message_human = message
          end
        }
        result = {
          :result        => 'invalid',
          :message       => e.message,
          :message_human => message_human,
        }
        return result
      end
      return
    end

    begin
      Channel::Sendmail.new.send(
        {
          :from    => email,
          :to      => 'emailtrytest@znuny.com',
          :subject => 'test',
          :body    => 'test',
        },
        nil
      )
    rescue Exception => e
      message_human = ''
      translationMap.each {|key, message|
        if e.message =~ /#{Regexp.escape(key)}/i
          message_human = message
        end
      }
      result = {
        :result        => 'invalid',
        :message       => e.message,
        :message_human => message_human,
      }
      return result
    end
    return
  end

  def email_probe_inbound(params)

    # validate params
    if !params[:adapter]
      raise 'need :adapter param'
    end

    # connection test
    translationMap = {
      'authentication failed'                                     => 'Authentication failed!',
      'getaddrinfo: nodename nor servname provided, or not known' => 'Hostname not found!',
      'No route to host'                                          => 'No route to host!',
      'Connection refused'                                        => 'Connection refused!',
    }
    if params[:adapter] =~ /^imap$/i
      begin
        Channel::IMAP.new.fetch( { :options => params[:options] }, 'check' )
      rescue Exception => e
        message_human = ''
        translationMap.each {|key, message|
          if e.message =~ /#{Regexp.escape(key)}/i
            message_human = message
          end
        }
        result = {
          :result        => 'invalid',
          :message       => e.message,
          :message_human => message_human,
        }
        return result
      end
      return
    end

    begin
      Channel::POP3.new.fetch( { :options => params[:options] }, 'check' )
    rescue Exception => e
      message_human = ''
      translationMap.each {|key, message|
        if e.message =~ /#{Regexp.escape(key)}/i
          message_human = message
        end
      }
      result = {
        :result        => 'invalid',
        :message       => e.message,
        :message_human => message_human,
      }
      return result
    end
    return
  end

  def mxers(domain)
    mxs = Resolv::DNS.open do |dns|
      ress = dns.getresources(domain, Resolv::DNS::Resource::IN::MX)
      ress.map { |r| [r.exchange.to_s, IPSocket::getaddress(r.exchange.to_s), r.preference] }
    end
    mxs
  end

  def setup_done
    #return false
    count = User.all.count()
    done = true
    if count <= 2
      done = false
    end
    done
  end

  def setup_done_response
    if !setup_done
      return false
    end
    render :json => {
      :setup_done     => true,
      :import_mode    => Setting.get('import_mode'),
      :import_backend => Setting.get('import_backend'),
    }
    true
  end

end