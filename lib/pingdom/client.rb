require File.join(File.dirname(__FILE__), '..', 'pingdom-ruby') unless defined? Pingdom

module Pingdom
  class Client

    attr_accessor :limit

    def initialize(options = {})
      @options = options.with_indifferent_access.reverse_merge(:http_driver => Faraday.default_adapter)

      raise ArgumentError, "an application key must be provided (as :key)" unless @options.key?(:key)

      @connection = Faraday::Connection.new(:url => "https://api/pingdom.com/api/2.0/", ssl: {verify: false}) do |builder|
        builder.url_prefix = "https://api.pingdom.com/api/2.0"

        # builder.adapter :logger, @options[:logger]
        builder.request  :url_encoded
        builder.adapter @options[:http_driver]

        # builder.use Gzip # TODO: write GZip response handler, add Accept-Encoding: gzip header
        builder.response :json, content_type: /\bjson$/
        builder.use Tinder::FaradayResponse::WithIndifferentAccess

        builder.basic_auth @options[:username], @options[:password]
        builder.headers["App-Key"] = @options[:key]

        if @options[:account_email]
          builder.headers["Account-Email"] = @options[:account_email]
        end
      end
    end

    # probes => [1,2,3] #=> probes => "1,2,3"
    def prepare_params(options)
      options.each do |(key, value)|
        options[key] = Array.wrap(value).map(&:to_s).join(',')
        options[key] = value.to_i if value.acts_like?(:time)
      end

      options
    end

    def get(uri, params = {}, &block)
      response = @connection.get(@connection.build_url(uri, prepare_params(params)), &block)
      update_limits!(response.headers['req-limit-short'], response.headers['req-limit-long'])
      response
    end

    def put(uri, params = {}, &block)
      response = @connection.put(uri, params)
      update_limits!(response.headers['req-limit-short'], response.headers['req-limit-long'])
      response
    end

    def post(uri, params = {}, &block)
      response = @connection.post(uri, params)
      update_limits!(response.headers['req-limit-short'], response.headers['req-limit-long'])
      response
    end

    def update_limits!(short, long)
      @limit ||= {}
      @limit[:short]  = parse_limit(short)
      @limit[:long]   = parse_limit(long)
      @limit
    end

    # "Remaining: 394 Time until reset: 3589"
    def parse_limit(limit)
      if limit.to_s =~ /Remaining: (\d+) Time until reset: (\d+)/
        { :remaining => $1.to_i,
          :resets_at => $2.to_i.seconds.from_now }
      end
    end

    def test!(options = {})
      Result.parse(self, get("single", options)).first
    end

    #
    # Create a new Check with mandatory options
    # Use options hash for addtional options
    # Obtains and returns created Check object
    #
    def create_check(name, type, host, options={})
      raise RuntimeError.new "Name, type and host are mandatory. [#{name}] [#{type}] [#{host}]" if (name.nil? || type.nil? || host.nil?)
      raise RuntimeError.new "Options must be a hash. [#{options.class}:#{options}]" unless options.is_a? Hash

      # Set mandatory parameters
      options['name'] = name
      options['type'] = type
      options['host'] = host

      response = post('checks', options)
      return nil if response.status != 200
      check(response.body['check']['id'])
    end

    def checks(options = {})
      Check.parse(self, get("checks", options))
    end

    def check(id)
      Check.parse(self, get("checks/#{id}")).first
    end

    def update_check(check, params)
      raise RuntimeError.new "Not a valid check [#{check}]" unless check.is_a? Pingdom::Check
      put("checks/#{check.id}", params)
    end

    # Check ID
    def results(id, options = {})
      options.reverse_merge!(:includeanalysis => true)
      Result.parse(self, get("results/#{id}", options))
    end

    def probes(options = {})
      Probe.parse(self, get("probes", options))
    end

    def contacts(options = {})
      Contact.parse(self, get("contacts", options))
    end

    def summary(id)
      Summary.proxy(self, id)
    end

  end
end
