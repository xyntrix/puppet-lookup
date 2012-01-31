require 'yaml'

$ylookup_calls = 0

module Puppet::Parser::Functions
  newfunction(:ylookup, :type => :rvalue) do |args|

    recurse_limit = 6   # Prevent endless recursion
    $ylookup_calls+=1
    raise Puppet::ParseError, "Recursive limit reached: #{recurse_limit}" if $ylookup_calls > recurse_limit

    # ---------------------------------------------
    # Debug Parameters
    # ---------------------------------------------
    @debug_prefix = 'ylookup(): '                                               # Make the debug output clear that it is originating from ylookup()
    @lookup_debug = true if lookupvar('lookup_debug') == true                   # General debugging
    @lookup_file_debug = true  if lookupvar('lookup_file_debug') == true        # Looking for .yaml files
    @lookup_hash_debug = true if lookupvar('lookup_hash_debug') == true or lookupvar('lookup_debug') == true    # Debug output of hash values
    @lookup_type_debug = true if lookupvar('lookup_type_debug') == true         # Debug result types (string, number, array, hash)
    @vtf_debug = true if lookupvar('lookup_vtf_debug') == true                  # Debug var_to_fact() calls.
    @debug_pretty = true if lookupvar('lookup_debug_pretty') != false           # Default to pretty debug 

    # the Parser object is un-necessary in 2.6 
    # SEE: http://docs.puppetlabs.com/guides/custom_functions.html#notes-on-backward-compatibility
    #parser = Puppet::Parser::Parser.new(environment)

    # we parse the precedence here because the best place to specify
    # it would be in site.pp but site.pp is only evaluated at startup
    # so $fqdn etc would have no meaning there, this way it gets evaluated
    # each run and has access to the right variables for that run
    def var_to_fact str
      while str =~ /%\{(.+?)\}/
        token = $1
        debug @debug_prefix + "vtf: var_to_fact matched '#{token}' to string '#{str}'" if @vtf_debug
        fact = lookupvar token
        debug @debug_prefix + "vtf: lookupvar '#{token}' returned '#{fact}'" if @vtf_debug
        # --
        if fact == "" 
            debug @debug_prefix + "vtf: fact '#{fact}' is not in scope. calling self for fact." if @vtf_debug
            # recursive call... bad idea?
            fact = function_ylookup([token.to_s])
            #$ylookup_calls+=1
            debug @debug_prefix + "vtf: fact '#{token}' is found to be '#{fact}'" if @vtf_debug
        end
        # --
        raise(Puppet::ParseError, "Unable to find value for #{str}") if fact.nil?
        str.gsub!(/%\{#{$1}\}/, fact)
      end
      debug @debug_prefix + "vtf: returning #{str}" if @vtf_debug 
      str
    end

    # --------------------------------
    # what are we looking for?
    # --------------------------------
    lookup_name  = args[0]
    default      = args[1]
    lookup_order_path = lookupvar('lookup_order_path') # will always return a string / array (even an empty one)
    lookup_order_files = lookupvar('lookup_order_files') # will always return a string / array (even an empty one)
    # agreed ohad. a hack, but this does ensure the var is initialized in a way we expect
    order_path        = (args[2] || lookup_order_path).to_a.join("!LoOKUpp!").split("!LoOKUpp!")
    order_files       = (args[3] || lookup_order_files).to_a.join("!LoOKUpp!").split("!LoOKUpp!")

    raise Puppet::ParseError, "Unable to find any lookup_order_path var set(#{order_path}), make sure you install it in site.pp" if order_path.nil? or (order_path[0] == "undefined")
   order_files = [ "data", "values" ] if order_files.nil? or (order_files[0] == "undefined")

    debug @debug_prefix + "--------------------------------------------------------------------" if @lookup_debug and @debug_pretty
    debug @debug_prefix + "Looking for subject '#{lookup_name}' " if @lookup_debug
    debug @debug_prefix + "Relative Lookup Path: '#{order_path.inspect}'" if @lookup_debug
    debug @debug_prefix + "Suffix Lookup Filespec: '#{order_files.inspect}'" if @lookup_debug
    debug @debug_prefix + "--------------------------------------------------------------------" if @lookup_debug and @debug_pretty

    # --------------------------------
    # expand any variables
    # --------------------------------
    order_path.map! { |var| var_to_fact var }

    # --------------------------------
    # search through puppet module path and lookup order_path
    # --------------------------------
    datafiles = Array.new
    env = lookupvar('environment').to_sym
    debug @debug_prefix + "Environment: '#{env}'" if @lookup_debug
    env_path = Puppet.settings.instance_variable_get(:@values)[env][:modulepath].nil? ? Puppet.settings.value(:modulepath).split(":") : self.split(":")
    debug @debug_prefix + "Environment path: '#{env_path.inspect}'" if @lookup_file_debug
    debug @debug_prefix + "--------------------------------------------------------------------" if @lookup_debug and @debug_pretty
    begin
      order_path.each do |data_file|
        env_path.each do |module_path|
          # where our data file is located at
          order_files.each do |filespec|
            file = "#{module_path}/#{data_file}/#{filespec}.yaml"
            debug @debug_prefix + "Looking for '#{file}'" if @lookup_file_debug
            datafiles << file if File.exists?(file)
          end
        end
      end
    rescue
      raise Puppet::ParseError, "Something went wrong while looking for a datafile for #{lookup_name} - #{$!}"
    end

    debug @debug_prefix + "Found the following relevant data files: #{datafiles.join(", ")}" if @lookup_file_debug
    # parse our data files

    found = false
    result = ""
    datafiles.each do |file|
      begin
        next if found
        # NOTE: un-necessary in 2.6 per http://docs.puppetlabs.com/guides/custom_functions.html#notes-on-backward-compatibility
        #parser.watch_file file     
        debug @debug_prefix + "scanning #{file}" if @lookup_debug or @lookup_file_debug
        result = YAML.load_file(file)[lookup_name]
        debug @debug_prefix + "YAML.load_file(#{file})[lookup_name] result: '#{result}'" if @lookup_debug and result
        if result and result.size > 0
          found = true
          if result.is_a?(String) 
            debug @debug_prefix + "result is a String" if @lookup_type_debug
            result = var_to_fact result
          elsif result.is_a?(Numeric)
            debug @debug_prefix + "result is Numeric" if @lookup_type_debug
            result = var_to_fact result.to_s
          elsif result.is_a?(Array)
            debug @debug_prefix + "result is a Array" if @lookup_type_debug
            result.map! { |r| 
              debug @debug_prefix + " - '#{r}'" if @lookup_type_debug
              # TODO: recursive Array of Arrays|Hashes
              var_to_fact r 
            } # replace values to facts if required.
          elsif result.is_a?(Hash)  
            debug @debug_prefix + "result is a Hash" if @lookup_type_debug or @lookup_hash_debug
            result.keys.each { |k| 
              #debug @debug_prefix + "hash key '#{k}'" if @lookup_type_debug or @lookup_hash_debug 
              # Hash-of-Hashes support
              if result[k].is_a?(Hash) 
                debug @debug_prefix + " [key] '#{k}':" if @lookup_type_debug or @lookup_hash_debug
                result[k].each { |subkey, subval|
                  #debug @debug_prefix + "  [subkey] '#{subkey}' => '#{result[k][subkey]}'" if @lookup_type_debug or @lookup_hash_debug
                  debug @debug_prefix + "  [subkey] '#{subkey}' => '#{subval}'" if @lookup_type_debug or @lookup_hash_debug
                  result[k][subkey] = var_to_fact subval
                }
              else 
                debug @debug_prefix + " '#{k}' => '#{result[k]}'" if @lookup_type_debug or @lookup_hash_debug
                result[k] = var_to_fact result[k]
              end
            }
            result.to_a.map! { |r| var_to_fact r } # replace values to facts if required.
          end
          debug @debug_prefix + "'#{lookup_name}' => '#{result}' : from '#{file}'" if @lookup_debug
        end
      rescue
        raise Puppet::ParseError, "Something went wrong while parsing #{file} - #{$!}"
      end
    end

    if not found or result.size == 0
      if default 
        return default
      else 
        raise Puppet::ParseError, "Unable to find value for #{lookup_name}"
      end
    else
      debug @debug_prefix + "RESULT: '#{lookup_name}' => '#{result}'" if @lookup_debug
      debug @debug_prefix + " Recursive calls: #{$ylookup_calls}" if @lookup_debug
      #return result.size == 1 ? result.to_s : result
      $ylookup_calls = 0
      return result
    end
  end
end
