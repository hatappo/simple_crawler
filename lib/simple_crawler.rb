# encoding: utf-8

require 'logger'
require 'capybara'
require 'capybara/poltergeist'

module SimpleCrawler 
  class Conf
    attr_reader :list, :out, :wait_sec, :invalid_threashold, :headers, :scrape, :crawl

    def initialize(conf_file)
      raise RuntimeError, "confファイルのパスが設定されていません。" unless conf_file
      raise RuntimeError, "不正なconfファイルのパス：'#{conf_file}'" unless File.exist?(conf_file)

      # 初期値を設定
      @headers = {}
      @wait_sec = 1.0
      @invalid_threashold = 0
      @crawl  = Proc.new {|session, logger, scraping| logger.debug "クローリング処理が呼ばれました。 current_url='#{session.current_url}'"}
      @scrape = Proc.new {|session, logger, writer|   logger.debug "スクレイピング処理が呼ばれました。 current_url='#{session.current_url}'"}

      # 設定ファイルを内部DSLとして読み込む
      crawling_list, scraping_out, wait_sec_by_each_page, invalid_crawling_url_cnt_threashold, headers, user_agent = nil
      instance_eval File.read(conf_file)

      set_list(crawling_list)                                     if crawling_list
      set_out(scraping_out)                                       if scraping_out
      set_wait_sec(wait_sec_by_each_page)                         if wait_sec_by_each_page
      set_invalid_threashold(invalid_crawling_url_cnt_threashold) if invalid_crawling_url_cnt_threashold
      headers.each{|k, v| add_header(k, v)}                       if headers || headers.kind_of?(Hash)
      add_header("User-Agent", user_agent)                        if user_agent
    end

    # （必須）クローリングの対象URL一覧ファイルのパスをセット。
    private def set_list(path)
      if path.kind_of?(String)
        raise RuntimeError, "#{__method__} が存在しません。：'#{path}'" unless File.exist? path
      end
      @list = path
    end

    # （任意）スクレイピングの出力ファイルのパスをセット。
    private def set_out(path)
      p = path.to_s
      raise RuntimeError, "出力ファイルが既に存在します。：'#{path}'" if File.exist? p
      @out = p
    end

    # （任意）ページをクローリングする都度挟むsleep時間（秒）をセット。
    private def set_wait_sec(seconds)
      sec = seconds.to_f
      case sec
      when 0.0..3.0 # nothing to do in valid range
      else raise RuntimeError, "#{__method__} は #{valid_range} の範囲内でなければなりません：'#{seconds}'"
      end
      @wait_sec = sec 
    end

    # （任意）クローリングにおける不正なURLを許容回数をセット
    private def set_invalid_threashold(count)
      c = count.to_i
      raise RuntimeError, "#{__method__} は 0以上でなければいけません。：'#{count}'" if c < 0
      @invalid_threashold = c
    end

    # （任意）httpヘッダの内容を追加。
    private def add_header(name, value)
      n =  name.to_s.strip
      v = value.to_s.strip
      raise RuntimeError, "不正なhttpヘッダ名：'#{name}'" if n.empty?
      @headers[n] = v
    end

    # # （任意）httpヘッダにユーザ・エージェントをセット。
    # private def set_user_agent(value)
    #   self.add_header(, value)
    # end

    # （任意）スクレイピングの処理をセット。
    private def scraping(&block)
      @scrape = block
    end

    # （任意）クローリングの処理をセット。
    private def crawling(&block)
      @crawl = block
    end
  end

  class Runner
    attr_reader :conf, :logger, :dry_run

    class << self
      def extract_url(line)
        return '' unless line.kind_of? String
        splitted = line.split("\t")
        splitted[0].to_s.strip
      end

      def valid_url?(url)
        return false unless url.kind_of? String
        url.start_with?("http://", "https://")
      end
    end

    def initialize(conf, log_level, dry_run)
      @conf = conf
      @dry_run = dry_run
      @logger = Logger.new(STDERR)
      @logger.level = log_level

      @logger.info "configuration = #{@conf.inspect}"
    end

    private def run_with_writer(session, list, out)
      total_cnt, valid_cnt = 0, 0

      list.each do |line|
        invalid_cnt = total_cnt - valid_cnt
        if @conf.invalid_threashold > 0 and invalid_cnt >= @conf.invalid_threashold
          raise RuntimeError, "不正なURLの件数が閾値( #{@conf.invalid_threashold} )を超えたため【#{total_cnt}行目】で処理を停止します。"
        end
        total_cnt += 1

        status = {}
        status[:next_url] = SimpleCrawler::Runner.extract_url line
        @logger.debug "url='#{status[:next_url]}'."
        if not SimpleCrawler::Runner.valid_url? status[:next_url]
          @logger.info "スキップ! #{total_cnt}行目の不正なURLデータ:'#{line.chomp}'。"
          next
        end

        begin
          while status[:next_url] do
            session.visit status[:next_url]
            status[:next_url] = nil
            @conf.scrape.call(session, @logger, out)
            @conf.crawl.call(session, @logger, status)
            sleep @conf.wait_sec
          end
        rescue Exception => e
          @logger.info e
          next
        ensure
          sleep @conf.wait_sec
        end
        valid_cnt += 1
      end

      @logger.info "-------- 【総クローリングURL数=#{total_cnt}】, 【正常URL数=#{valid_cnt}】, 【異常URL数=#{total_cnt - valid_cnt}】 --------"
    end

    private def run_with_list(session, list)
      begin
        @logger.info "-------- 開始 --------"
        @logger.info "-------- DRY RUN (NO OPERATION) MODE --------" if @dry_run

        return if @dry_run

        if @conf.out
          File.open(@conf.out, "w") {|out| run_with_writer(session, list, out)}
        else
          run_with_writer(session, list, nil)
        end
      ensure
        @logger.info "-------- 終了　--------"
      end
    end

    public def run
      # @see https://github.com/teampoltergeist/poltergeist#poltergeist---a-phantomjs-driver-for-capybara
      Capybara.run_server = false
      Capybara.register_driver :poltergeist do |app|
        Capybara::Poltergeist::Driver.new(app)
      end
      session = Capybara::Session.new(:poltergeist)
      session.driver.headers = @conf.headers
      @logger.debug "session.driver.headers='#{session.driver.headers}'"

      case
      when @conf.list.kind_of?(Array)  then run_with_list(session, @conf.list)
      when @conf.list.kind_of?(String) then File.open(@conf.list, 'r') {|list| run_with_list(session, list)}
      else raise RuntimeError, "不正なURL一覧情報：'#{@conf.list}'"
      end
    end
  end
end




########################################
# main
########################################
if __FILE__ == $0
  require 'optparse'

  LOG_LEVELS = {
    'debug' => Logger::DEBUG,
    'info'  => Logger::INFO,
    'warn'  => Logger::WARN,
    'error' => Logger::ERROR,
    'fatal' => Logger::FATAL
  }

  OPTION = {}
  OPTION[:cfg] = nil
  OPTION[:dry_run] = true           # デフォルト動作では、実際には実行しない。
  OPTION[:log_level] = Logger::INFO # デフォルトは INFO

  OPT_PARSER = OptionParser.new()
  OPT_PARSER.version = '0.0.1'
  OPT_PARSER.on('-c', '--cfg=CONFIG_FILE', "Crawling configulation file path.") {|v| OPTION[:cfg] = v}
  OPT_PARSER.on(      '--[no-]run',        'No operation (dry run).')           {|v| OPTION[:dry_run] = !v}
  OPT_PARSER.on('-l', '--log=LOG_LEVEL',   LOG_LEVELS.keys.join(' | '))         {|v|
    OPTION[:log_level] = LOG_LEVELS[v]
    if OPTION[:log_level].nil?
      raise RuntimeError, "Invalid log level. Log level must be '#{LOG_LEVELS.keys.join(' | ')}'"
    end
  }

  OPT_PARSER.parse!(ARGV)

  LOGGER = Logger.new(STDERR)
  LOGGER.level = Logger::INFO
  LOGGER.info "OPTION = #{OPTION}"

  begin
    CONF   = SimpleCrawler::Conf.new(OPTION[:cfg])
    RUNNER = SimpleCrawler::Runner.new(CONF, OPTION[:log_level], OPTION[:dry_run])
    RUNNER.run()
  rescue Exception => e
    STDERR.puts 'FATAL -- : ' + e.message
    STDERR.puts e.backtrace
    STDERR.puts 'Aborting...'
  end
end
