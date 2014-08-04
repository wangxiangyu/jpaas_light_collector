require 'sinatra/base'
require 'json'
require "yaml"
require "logger"
require "database"
require "resolv"
require "cluster"


class Collector < Sinatra::Base
    disable :logging
    def self.configure
         config_file = ENV["CONFIG_FILE"] || File.expand_path("../config/collector.yml", File.dirname(__FILE__))
         @config=YAML.load_file(config_file)
         set :bind, '0.0.0.0'
         set :port, @config["listen_port"]
         set :server, 'puma'
    end
    attr_reader :config
    attr_reader :logger
    def self.connect_to_db
       begin
            CollectorDb.configure(@config)
       rescue =>e
            @logger.error "#{e.message},#{e.backtrace}"
       end
    end
    
    def self.setup_log 
       @logger=Logger.new(@config['logging']['file'])
       @logger.datetime_format = "%Y-%m-%d %H:%M:%S"
       @logger.formatter = proc do |severity, datetime, progname, msg|
           "[#{datetime}] #{severity} : #{msg}\n"
       end
       @logger.level = Logger::DEBUG
       set :logger, @logger
    end
    
    def get_cluster_by_ip(ip)
        cluster='unknown'
        result=DeaList.where(:ip=>ip)
        unless result.empty?
            cluster=result.first.cluster_num
        end
        cluster
    end

    def format(s)
        s.to_s.gsub(/^"/,"").gsub(/"$/,"").gsub(/^'/,"").gsub(/'$/,"")
    end

    after  do
	ActiveRecord::Base.clear_active_connections!
    end

     post '/collector/collect_instance_meta' do
      begin
        params = JSON.parse request.body.read
        instance_info={}
        instance_info['state']=params["state"]
        return {:rescode=>-1,:msg=>"instance state is not running"}.to_json unless instance_info['state']=="RUNNING"
        instance_info['time']=Time.now.to_i
        instance_info['host']=params["dea_ip"]
        instance_info['space']=params["tags"]["space_name"]
        instance_info['organization']=params["tags"]["org_name"]
        instance_info['bns_node']=params["tags"]["bns_node"]
        instance_info['app_name']=params["application_name"]
        instance_info['uris']=params["application_uris"].join(",")
        instance_info['instance_index']=params["instance_index"]
        instance_info['cluster_num']=get_cluster_by_ip(instance_info['host'])
        instance_info['warden_handle']=params["warden_handle"]
        instance_info['warden_container_path']=params["warden_container_path"]
        instance_info['state_starting_timestamp']=params["state_starting_timestamp"]
        instance_info['port_info']=params["instance_meta"]["prod_ports"].to_json.to_s
        instance_info['noah_monitor_port']=params["noah_monitor_host_port"]
        instance_info['instance_mgr_host_port']=params["instance_mgr_host_port"]
        instance_info['warden_host_ip']=params["warden_host_ip"]
        instance_info['instance_id']=params["instance_id"]
        instance_info['disk_quota']=params["limits"]["disk"]
        instance_info['mem_quota']=params["limits"]["mem"]
        instance_info['fds_quota']=params["limits"]["fds"]
        InstanceStatus.where(
            :instance_id=>instance_info['instance_id']
        ).first_or_create.update_attributes(instance_info)
        return {:rescode=>0,:msg=>"ok"}.to_json
      rescue => e
          settings.logger.error "#{e.message},#{e.backtrace}"
      end
    end

    post '/collector/collect_instance_resource' do
        begin
        params = JSON.parse request.body.read
        instance_info={}
        instance_info['instance_id']=params["instance_id"]
        instance_info['time']=Time.now.to_i
        instance_info['cpu_usage']=params["usage"]["cpu"]
        instance_info['mem_usage']=params["usage"]["mem"]
        instance_info['fds_usage']=params["usage"]["fds"]
        result=InstanceStatus.where(
              :instance_id=>instance_info['instance_id'],
              :state=>'RUNNING'
         )
        if result.empty?
            return {:rescode=>-1,:msg=>"instance doesn't exist"}.to_json
        else
        	host=result.first.host
        	instance_info['cluster_num']=get_cluster_by_ip(host)
            result.first.update_attributes(instance_info)
            return {:rescode=>0,:msg=>"ok"}.to_json
        end
        rescue => e
            settings.logger.error "#{e.message},#{e.backtrace}"
        end
    end

    get '/collector/instance_existence_check' do
        begin
            instance_id=params["instance_id"]
            if InstanceStatus.where(:instance_id=>instance_id,:state=>'RUNNING').empty?
                return {"status"=>"bad"}.to_json
            else
                return {"status"=>"ok"}.to_json
            end
        rescue => e
            settings.logger.error "#{e.message},#{e.backtrace}"
        end
    end
    post '/collector/collect_dea_info' do
       begin
           params = JSON.parse request.body.read
           dea_info={}
           dea_info["uuid"]=params["uuid"]
           dea_info["ip"]=params["ip"]
           dea_info["cluster_num"]=Cluster.get_cluster_by_ip(dea_info["ip"])
           dea_info["time"]=Time.now.to_i
           DeaList.where(
                :uuid=>dea_info["uuid"]
            ).first_or_create.update_attributes(dea_info)
           return {:rescode=>0,:msg=>"ok"}.to_json
       rescue => e
           settings.logger.error "#{e.message},#{e.backtrace}"
       end
   end

    post '/collector/state_update' do
       begin
           params = JSON.parse request.body.read
           ip=params["ip"]
           handle=params["handle"]
           state=params["state"]
           instance=InstanceStatus.where(:host=>ip,:warden_handle=>handle)
           if instance.empty?
                return {:rescode=>-1,:msg=>"container #{handle} on #{ip} does't exist"}.to_json
           else
                instance.update_all({:state=>state})
                return {:rescode=>0,:msg=>"ok"}.to_json
           end
       rescue => e
           settings.logger.error "#{e.message},#{e.backtrace}"
       end
    end

    get '/collector/state_query' do
       begin
           params = JSON.parse request.body.read
           ip=format(params["ip"])
           handle=format(params["handle"])
           instance=InstanceStatus.where(:host=>ip,:warden_handle=>handle)
           if instance.empty?
                return {:rescode=>-1,:msg=>"container #{handle} on #{ip} does't exist"}.to_json
           else
                return {:rescode=>0,:msg=>"ok",:state=>"#{instance.first.state}"}.to_json
           end
       rescue => e
           settings.logger.error "#{e.message},#{e.backtrace}"
       end
    end

    post '/collector/all_containers' do
       begin
           params = JSON.parse request.body.read
           ip=params["ip"]
           containers=params["containers"]
           instances=InstanceStatus.where(:host=>ip)
           instances.find_each do |instance|
                unless containers.include?(instance.warden_handle)
                    to_del_cnt=instance.to_del_cnt.to_i-1
                    instance.update(:to_del_cnt=>to_del_cnt)
                else
                    to_del_cnt=3
                    instance.update(:to_del_cnt=>to_del_cnt)
                end
           end
           return {:rescode=>0,:msg=>"ok"}.to_json
       rescue => e
           settings.logger.error "#{e.message},#{e.backtrace}"
       end
    end
    get '/collector/instance_expected_num' do
        begin
            app_info={}
            app_info['app_id']=params["app_id"]
            app_info['app_name']=params["app_name"]
            app_info['cluster_num']=params["cluster_num"]
            app_info['organization']=params["organization"]
            app_info['space']=params["space"]
            app_info['instance_num_expected']=params["instance_num_expected"]
            app_info['not_deleted']=params["not_deleted"]
            app_info['time']=Time.now.to_i
            InstanceNumExpected.where(
                :app_id=>app_info['app_id'],
                :cluster_num=>app_info['cluster_num'],
                :app_name=>app_info['app_name']
            ).first_or_create.update_attributes(app_info)
        end
    end
end
