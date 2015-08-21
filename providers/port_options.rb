#
# Cookbook Name:: freebsd
# Provider:: port_option
#
# Copyright 2012, ZephirWorks
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/mixin/shell_out'

include Chef::Mixin::ShellOut

action :create do
  if new_resource.source
    res = template new_resource.full_path do
      mode 0644
      source new_resource.source
      action :nothing
    end
  else
    output = []
    output << '# This file is auto-generated by Chef.'

    if new_resource.file_writer
      output << "# Options for #{new_resource.file_writer}"
      output << "_OPTIONS_READ=#{new_resource.file_writer}"
    end

    options = @current_resource.default_options
    options.merge!(@current_resource.current_options)
    options.merge!(new_resource.options)

    options.each_pair do |k, v|
      output << "#{v ? 'WITH' : 'WITHOUT'}_#{k}=true"
    end

    res = file new_resource.full_path do
      mode 0644
      content output.join("\n") + "\n"
      action :nothing
    end
  end
  res.run_action(:create)
  new_resource.updated_by_last_action(res.updated_by_last_action?)
end

def load_current_resource
  @current_resource = Chef::Resource::FreebsdPortOptions.new(@new_resource.name)

  @current_resource.default_options(load_default_options)

  if ::File.exist?(new_resource.full_path)
    @current_resource.current_options(load_current_options)
  end

  @current_resource
end

protected

def load_default_options
  default_options = ports_makefile_options_variable_value.map do |option, value|
    [option, value == 'on']
  end
  default_options = Hash[default_options]

  Chef::Log.debug "#{new_resource} Default options: #{default_options.inspect}"
  default_options
end

def load_current_options # rubocop:disable Metrics/AbcSize
  current_options = {}

  ::File.open(new_resource.full_path, 'r') do |f|
    f.readlines.each do |line|
      line.strip!
      next if line =~ /^\s*#/

      if line =~ /^\s*(\w+)=(.+)$/
        key = Regexp.last_match[1]
        value = Regexp.last_match[1]

        if key == '_OPTIONS_READ'
          new_resource.file_writer(value)
        elsif key =~ /^(WITH(?:OUT)?)_(.+)$/
          current_options[Regexp.last_match[2]] = Regexp.last_match[1] == 'WITH'
        else
          Chef::Log.warn "#{new_resource} unexpected key: #{key}=#{value}"
        end
      else
        Chef::Log.warn "#{new_resource} unexpected line: #{line}"
      end
    end
  end

  Chef::Log.debug "#{new_resource} Current options: #{current_options.inspect}"
  current_options
end

def port_path
  whereis = shell_out!("whereis -s #{@new_resource.name}", env: nil)
  unless path == whereis.stdout[/^#{@new_resource.name}:\s+(.+)$/, 1]
    fail Chef::Exceptions::Package, "Could not find port with the name #{@new_resource.name}"
  end
  path
end

def ports_makefile_options_variable_value(variable = 'OPTIONS')
  make_v = shell_out!("make -V #{variable}", cwd: port_path, env: nil, returns: [0, 1])
  make_v.stdout.strip.scan(/(\S+?) ".+?" (\S+?)\b/)
end
