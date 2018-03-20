require "envlink/version"

module Envlink
  class Linker
    def initialize(config_hash, r10k_config_hash)
      @config_hash = config_hash
      @r10k_config_hash = r10k_config_hash
    end

    def ensureLinks
      # Iterate over all environments
      env_h = Dir.new(@config_hash['environment_path'])
      env_h.each {|entry|
        if entry.start_with?('.')
          next
        end
        
        path = "#{@config_hash['environment_path']}/#{entry}"
        if ! Dir.exist?(path)
          next
        end

        # Can this directory be classified to one of the control repos in our config?
        control_repo = classifyEnvironmentToControlRepo(entry)
        if ! control_repo.nil?
          ensureLinksInPathForControlRepo(path, entry, control_repo)
        end
      }
    end

    def classifyEnvironmentToControlRepo(environment)
      control_repo = nil

      @config_hash['links'].keys.each { |r10k_source|
        if ! @r10k_config_hash['sources'].has_key?(r10k_source)
          STDERR.puts "The envlink configuration references r10k source \"#{r10k_source}\", but it does not exist in the r10k configuration file."
          next
        end
        allowPrefix = if @r10k_config_hash['sources'][r10k_source].has_key?('prefix') &&
                         @r10k_config_hash['sources'][r10k_source]['prefix']
                          true
                        else
                          false
                        end

        if allowPrefix && environment.start_with?("#{r10k_source}_")
          control_repo = r10k_source
          break
        elsif environment == r10k_source
          control_repo = r10k_source
        end
      }

      control_repo
    end

    def ensureLinksInPathForControlRepo(path, environment, control_repo)
      desired_links = @config_hash['links'][control_repo]

      desired_links.each { |rules|
        if rules.has_key?('map')
          map = rules['map']
        else
          map = {}
        end

        if map.has_key?(environment)
          preferred_target = map[environment]
        else
          preferred_target = environment
        end

        # Does the preferred target exist as a directory we can link to inside the r10k source?
        target_root = @r10k_config_hash['sources'][rules['r10k_source']]['basedir']
        if Dir.exist?("#{target_root}/#{preferred_target}")
          target = "#{target_root}/#{preferred_target}"
          output_info = true
        else
          target = "#{target_root}/#{rules['fallback_branch']}"
          output_info = false
        end

        if doLink(target, "#{path}/#{rules['link_name']}") && output_info
          puts "#{environment} is linked to the #{preferred_target} branch of #{rules['r10k_source']}"
        end
      }
    end

    def doLink(target, link_name)
      if File.symlink?(link_name)
        if File.readlink(link_name) == target
          return false
        end
        File.unlink(link_name)
      end

      File.symlink(target, link_name)
      true
    end
  end
end
