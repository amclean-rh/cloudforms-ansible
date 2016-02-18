#!/bin/env ruby

begin

  require 'open3'
  require 'json'
  
  # Method for logging.  Adjust accordingly when you're in automate.
  def log(level, message)
    @method = 'refresh_inventory'
#   $evm.log(level, "#{@method} - #{message}")
    puts("#{level.upcase} : #{@method} - #{message}")
  end

  # Using open3 calls our tower-cli command.
  # Arguments to pass to tower-cli should be passed as an array.
  # Returns a ruby hash of the JSON response from tower-cli.
  # A non-zero exit from tower-cli will call a raise.  Any other error handling
  # within the JSON payload is left to the user.
  def call_tower_cli(arg_=[])
    tower_cli_cmd="/usr/bin/tower-cli"
    # Remove any formatting commands we may be passed.  We will force JSON
    [ "-f", "--format", "json", "human" ].each { | search |
      if args.index(search)
        args=args.pop(args.index(search))
      end
    }

    args.push("-f").push("json")

    Open3.popen3(tower_cli_cmd + " " + args.join(" ")) { | stdin, stdout, stderr, wait_thr |

      exit_status=wait_thr.value.exitstatus

      if exit_status != 0
        raise "Command <#{tower_cli_cmd}> Arguments <#{args.join(", ")} Returned <#{exit_status}>.  STDOUT: <#{stdout.readlines} STDERR: <#{stderr.readlines}"
      end

      return(JSON.parse(stdout.readlines.join()))
    }
  end

  # - Finds an object within tower by it's name.  Manages pagination.
  # - The first argument is the type 'group', 'host', 'user', etc.  Anything
  #   that has a 'list' argument will work fine.
  # - We then iterate over the results until the first 'name' match is found
  #   returning that JSON object.
  # - Pagination is addressed by search all pages until the set is exhausted.
  # - On no match an empty hash is returned.
  def find_by_name(type, name)
    finished=0
    tower_cli_arguments=[type, "list"]
    until finished == 1
      output=call_tower_cli( tower_cli_arguments )
      output["results"].each { | type_hash |
        if type_hash["name"] == name
          return(type_hash)
        end
      }
      if output["next"]
        tower_cli_arguments=[type, "list", "--page", output["next"]]
      else
        finished=1
      end
    end

    return({})
  end

  # Helper to add a host (by name) to a group (by name).
  def add_host_to_group(host_name, group_name)
  
    host=find_by_name("host", host_name)
    group=find_by_name("group", group_name)

    unless host["id"]
      raise "Unable to find a valid host ID using name <#{host_name}>.  Has inventory been refreshed after the host was provisioned?"
    end

    unless group["id"]
      raise "Unable to find a valid group using name <#{credential_name}>"
    end

    call_tower_cli([ "host", "associate", "--group", group["id"], "--host", host["id"]])
  end

  # Helper to add attributes to a host (by name).
  # Attributes is a hash of name => value pairs to set.
  # eg:
  #  "ansible_ssh_host" => "192.168.10.10"
  #  "ansible_ssh_user" => "cloud-user"
  #  "ansible_become" => "true"
  #  "ansible_become_user" => "root"
  #  "ansible_become_method" => "sudo"
  def add_attributes_to_host(host_name, attributes)

    host=find_by_name("host", host_name)

    unless host["id"]
      raise "Unable to find a valid host ID using name <#{host_name}>.  Has inventory been refreshed after the host was provisioned?"
    end

    # Build our attributes yaml.
    content=["---"]
    attributes.each { | name, value |
      content.push("#{name}: #{value}");
    }

    # write our attributes hash out to temporary file.
    File.write("/tmp/ansible-#{$$}.yaml", content.join("\n") + "\n")

    call_tower_cli(["host", "modify", host["id"], "--variables", "/tmp/ansible-#{$$}.yaml"])
  end

rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
end
