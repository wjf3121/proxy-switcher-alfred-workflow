#!/usr/bin/env ruby

require "yaml"
require "json"

class Item
  def initialize
    @title = ""
    @subtitle = ""
    @icon = {}
    @arg = ""
  end

  def to_json(options = {})
    hash = {"uid": @uid, "type": @type, "title": @title, "subtitle": @subtitle, "arg": @arg, "icon": @icon}
    hash.to_json
  end

end

class ItemList < DelegateClass(Array)
  def initialize(items=[])
     @items = items
     super items
  end

  def to_json(options = {})
    hash = {"items": @items}
    hash.to_json
  end

end

class ProxySwitcher

  class Config

    attr :proxies

    CONFIG_FILE = File.expand_path '~/.proxyswitcher.rc'

    def initialize(service='Wi-Fi')
      if test ?e, CONFIG_FILE
        @proxies = YAML.load(IO.read(CONFIG_FILE)).map { |k, v| ProxyOption.buildProxy(service, k, v) }
      end
    end
  end

  PRIMARY_SERVICE_CMD = <<-'EOF'
SERVICE_GUID=`printf "open\nget State:/Network/Global/IPv4\nd.show" | \
scutil | grep "PrimaryService" | awk '{print $3}'`
SERVICE_NAME=`printf "open\nget Setup:/Network/Service/$SERVICE_GUID\nd.show" |\
scutil | grep "UserDefinedName" | awk -F': ' '{print $2}'`
echo $SERVICE_NAME
  EOF

  def initialize
    @service = self.primary_service
    @proxies = Config.new(@service).proxies
  end

  def primary_service
    `#{PRIMARY_SERVICE_CMD}`.chomp
  end

  def to_json(options = {})
    ItemList.new(@proxies).to_json
  end

  class ProxyOption < Item

    def self.buildProxy(service, name, options)
      case name
      when 'AutoDiscoveryProxy'
        ProxyAutoDiscovery.new(service)
      when 'AutoProxy'
        AutoProxy.new(service, options)
      else
        ProxyOption.new(service, name, options)
      end
    end

    Names = {
      'AutoDiscoveryProxy' => 'proxyautodiscovery',
      'AutoProxy' => 'autoproxy',
      'SocksProxy' => 'socksfirewallproxy',
      'HTTPProxy' => 'webproxy',
      'HTTPSProxy' => 'securewebproxy',
      'FTPProxy' => 'ftpproxy',
      'RTSPProxy' => 'streamingproxy',
      'GopherProxy' => 'gopherproxy'
    }

    attr :human_name

    GET_INFO_CMD = "networksetup -get%s '%s'"
    TURN_ON_CMD = "networksetup -set%s '%s' '%s' '%s' %s %s %s"
    TURN_OFF_CMD = "networksetup -set%sstate '%s' off"

    def initialize(service, name, options={})
      @title = ""
      @icon = {}
      @service = service
      @human_name = name
      @name = Names[name]
      @arg = ""
      self.parse_options(options)
      self.fetch_info
      @uid = @name
      @subtitle = @service
      @icon[:path] = "%s.png" % @status
    end

    def parse_options(options)
      @url = options['URL']
      @server = options['Host']
      @port = options['Port']
      @auth = options['Auth']
      @username = options['Username']
      @password = options['Password']
    end

    def fetch_info
      IO.popen GET_INFO_CMD % [@name, @service] do |io|
        io.each do |line|
          line.chomp!
          if line =~ /^Enabled: (Yes|No)/
            if $1 == 'Yes'
              @status = 'On'
            else
              @status = 'Off'
            end
          elsif line.start_with? 'Server:' and @status == 'On'
            @server = line
          elsif line.start_with? 'Port:' and @status == 'On'
            @port = line
          end
        end
      end
      if @status == 'On'
        @arg = TURN_OFF_CMD % [@name, @service, 'off']
      else
        if @auth
          @arg = TURN_ON_CMD % [@name, @service, @server, @port, 'on', "'#@username'", "'#@password'"]
        else
          @arg = TURN_ON_CMD % [@name, @service, @server, @port, '', "", ""]
        end
      end
      @title = "%s: %s, %s, %s" % [@human_name, @status, @server, @port]
    end

  end

  class ProxyAutoDiscovery < ProxyOption

    SET_STATE_CMD = "networksetup -setproxyautodiscovery '%s' %s"

    def initialize(service)
      super(service, 'AutoDiscoveryProxy')
    end

    def fetch_info
      IO.popen ProxyOption::GET_INFO_CMD % [@name, @service] do |io|
        io.each do |line|
          line.chomp!
          if line =~ /: (On|Off)/
            if $1 == 'On'
              @status = 'On'
              @reversed_status = 'off'
            else
              @status = 'Off'
              @reversed_status = 'on'
            end
          end
        end
      end
      @arg = SET_STATE_CMD % [@service, @reversed_status]
      @title = "%s: %s" % [@human_name, @status]
    end
  end

  class AutoProxy < ProxyOption

    GET_INFO_CMD = "networksetup -getautoproxyurl '%s'"
    TURN_ON_CMD = "networksetup -set%surl '%s' '%s'"
    TURN_OFF_CMD = "networksetup -set%sstate '%s' off"

    def initialize(service, options)
      super(service, 'AutoProxy', options)
    end

    def fetch_info
      IO.popen GET_INFO_CMD % @service do |io|
        io.each do |line|
          line.chomp!
          if line =~ /^Enabled: (Yes|No)/
            if $1 == 'Yes'
              @status = 'On'
              @reversed_status = 'off'
            else
              @status = 'Off'
              @reversed_status = 'on'
            end
          elsif line.start_with? 'URL:' and @status == 'On'
            @url = line
          end
        end
      end
      if @status == 'On'
        @arg = TURN_OFF_CMD % [@name, @service, 'off']
      else
        @arg = TURN_ON_CMD % [@name, @service, @url]
      end
      @title = "%s: %s, %s" % [@human_name, @status, @url]
    end
  end
end

if $0 == __FILE__
  puts JSON.pretty_generate(ProxySwitcher.new)
end
