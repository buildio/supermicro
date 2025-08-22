# frozen_string_literal: true

module Supermicro
  class Spinner
    SPINNERS = {
      dots: {
        frames: ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'],
        interval: 0.08
      },
      line: {
        frames: ['-', '\\', '|', '/'],
        interval: 0.1
      },
      arrow: {
        frames: ['←', '↖', '↑', '↗', '→', '↘', '↓', '↙'],
        interval: 0.1
      },
      bounce: {
        frames: ['⠁', '⠂', '⠄', '⡀', '⡈', '⡐', '⡠', '⣀', '⣁', '⣂', '⣄', '⣌', '⣔', '⣤', '⣥', '⣦', '⣮', '⣶', '⣷', '⣿', '⡿', '⠿', '⢟', '⠟', '⡛', '⠛', '⠫', '⢋', '⠋', '⠍', '⡉', '⠉', '⠑', '⠡', '⢁'],
        interval: 0.08
      },
      bar: {
        frames: ['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█', '▇', '▆', '▅', '▄', '▃', '▂'],
        interval: 0.08
      }
    }
    
    def initialize(message = "Working", type: :dots, color: :cyan)
      @message = message
      @type = type
      @color = color
      @running = false
      @thread = nil
      @current_frame = 0
      @spinner_config = SPINNERS[@type] || SPINNERS[:dots]
      @start_time = nil
      @last_update = nil
      @max_width = 0  # Track the maximum width we've printed
    end
    
    def start
      return if @running
      @running = true
      @start_time = Time.now
      @current_frame = 0
      
      @thread = Thread.new do
        while @running
          render
          sleep @spinner_config[:interval]
          @current_frame = (@current_frame + 1) % @spinner_config[:frames].length
        end
      end
    end
    
    def update(message)
      @message = message
      @last_update = Time.now
      # Immediately render to show the update
      render if @running
    end
    
    def stop(final_message = nil, success: true)
      return unless @running
      @running = false
      @thread&.join
      
      # Clear the spinner line completely
      print "\r\033[2K"
      
      if final_message
        icon = success ? "✓".green : "✗".red
        elapsed = Time.now - @start_time
        time_str = elapsed > 1 ? " (#{elapsed.round(1)}s)" : ""
        puts "#{icon} #{final_message}#{time_str}"
      end
    end
    
    def with_spinner
      start
      begin
        yield self
      ensure
        stop
      end
    end
    
    private
    
    def render
      frame = @spinner_config[:frames][@current_frame]
      elapsed = Time.now - @start_time
      time_str = elapsed > 2 ? " (#{elapsed.round}s)" : ""
      
      # Build the output string without color codes to calculate real width
      text_content = "#{frame} #{@message}#{time_str}"
      current_width = text_content.length
      
      # Track maximum width seen
      @max_width = current_width if current_width > @max_width
      
      # Pad with spaces to clear any leftover text from longer previous messages
      padding = @max_width > current_width ? " " * (@max_width - current_width) : ""
      
      # Build the colored output
      output = "\r#{frame.send(@color)} #{@message}#{time_str}#{padding}"
      
      # Print without newline and flush immediately
      print output
      $stdout.flush
    end
  end
  
  module SpinnerHelper
    def with_spinner(message, type: :dots, color: :cyan, &block)
      return yield if respond_to?(:verbosity) && verbosity > 0
      
      spinner = Spinner.new(message, type: type, color: color)
      spinner.start
      
      begin
        result = yield(spinner)
        spinner.stop("#{message} - Complete", success: true)
        result
      rescue => e
        spinner.stop("#{message} - Failed", success: false)
        raise e
      end
    end
    
    def show_progress(message, duration: nil, &block)
      if duration
        # Show progress bar if duration is known
        with_progress_bar(message, duration, &block)
      else
        # Show spinner if duration is unknown
        with_spinner(message, &block)
      end
    end
    
    private
    
    def with_progress_bar(message, duration, &block)
      return yield if respond_to?(:verbosity) && verbosity > 0
      
      start_time = Time.now
      width = 30
      
      thread = Thread.new do
        while true
          elapsed = Time.now - start_time
          progress = [elapsed / duration, 1.0].min
          filled = (progress * width).round
          bar = "█" * filled + "░" * (width - filled)
          percent = (progress * 100).round
          
          print "\r#{message}: [#{bar}] #{percent}%"
          $stdout.flush
          
          break if progress >= 1.0
          sleep 0.1
        end
      end
      
      begin
        result = yield
        thread.join
        print "\r\e[K"
        puts "✓ #{message} - Complete".green
        result
      rescue => e
        thread.kill
        print "\r\e[K"
        puts "✗ #{message} - Failed".red
        raise e
      end
    end
  end
end