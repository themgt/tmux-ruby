require "filesize"
require "tempfile"

module Tmux
  class Buffer
    # @return [Number]
    attr_reader :number
    # @return [Session]
    attr_reader :session
    # @return [Filesize]
    def initialize(number, session)
      @number, @session, @size = number, session
      unless server.version >= "1.3"
        # we do not need a temporary file for tmux versions that can
        # directly load/save from/to stdin/stdout
        @file = Tempfile.new("buffer")
      end
    end

    # @!attribute [r] size
    #
    # @param [Boolean] force_reload Ignore frozen state if true
    # @return [Filesize]
    def size(force_reload = false)
      if @size && !force_reload
        @size
      else
        Filesize.new(@session.buffers_information[number][:size].to_i)
      end
    end

    # Receive the buffer's data.
    #
    # @param [Boolean] force_reload Ignore frozen state if true
    # @return [String]
    def data(force_reload = false)
      # note: we cannot use show-buffer because that would escape tabstops
      if @data && !force_reload
        @data
      else
        if server.version >= "1.3"
          return server.invoke_command "save-buffer -b #@number #{target_argument} -"
        else
          server.invoke_command "save-buffer -b #@number #{target_argument} #{@file.path}"
          return @file.read
        end
      end
    end

    # Set the buffer's data.
    #
    # @param [String] new_data
    # @return [String]
    def data=(new_data)
      # FIXME maybe some more escaping?
      server.invoke_command "set-buffer -b #@number #{target_argument} \"#{new_data}\""
      @data = data(true) if @frozen
      @size = size(true)
    end

    # Saves the contents of a buffer.
    #
    # @param [String] file The file to write to
    # @param [Boolean] append Append to instead of overwriting the file
    # @tmux save-buffer
    # @return [void]
    def save(file, append = false)
      flag = append ? "-a" : ""
      server.invoke_command "save-buffer #{flag} -b #@number #{target_argument} #{file}"
    end
    alias_method :write, :save

    # By default, Buffer will not cache its data but instead query it each time.
    # By calling this method, the data will be cached and not updated anymore.
    #
    # @return [void]
    def freeze!
      @frozen = true
      @data = data
      @size = size
    end

    # @!attribute [r] server
    #
    # @return [Server]
    def server
      @session.server
    end

    # Deletes a buffer.
    #
    # @tmux delete-buffer
    # @return [void]
    def delete
      freeze! # so we can still access its old value
      server.invoke_command "delete-buffer -b #@number #{target_argument}"
    end

    # @return [String] The content of a buffer
    def to_s
      text
    end

    # Pastes the content of a buffer into a {Window window} or {Pane pane}.
    #
    # @param [Window] target The {Pane pane} or {Window window} to
    #   paste the buffer into. Note: {Pane Panes} as as target are only
    #   supported since tmux version 1.3.
    # @param [Boolean] pop If true, delete the buffer from the stack
    # @param [Boolean] translate If true, any linefeed (LF) characters
    #   in the paste buffer are replaced with carriage returns (CR)
    # @param [String] separator Replace any linefeed (LF) in the
    #   buffer with this separator. +translate+ must be false.
    #
    # @tmux paste-buffer
    # @tmuxver &gt;=1.3 for pasting to {Pane panes}
    # @return [void]
    # @see Window#paste
    # @see Pane#paste
    def paste(target = nil, pop = false, translate = true, separator = nil)
      if server.version < "1.3"
        if separator || target.is_a?(Pane)
          raise Exception::UnsupportedVersion, "1.3"
        end
      end

      flag_pop       = pop ? "-d" : ""
      flag_translate = translate ? "" : "-r"
      flag_separator = separator ? "" : "-s \"#{separator}\"" # FIXME escape
      window_param   = target ? "-t #{target.identifier}" : ""
      server.invoke_command "paste-buffer #{flag_pop} #{flag_translate} #{flag_separator} #{window_param}"
    end

    private
    def target_argument
      if server.version < "1.5"
        "-t #{@session.identifier}"
      else
        ""
      end
    end
  end
end
