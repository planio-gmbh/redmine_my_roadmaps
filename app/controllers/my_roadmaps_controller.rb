# My Roadmaps - Redmine plugin to expose global roadmaps 
# Copyright (C) 2012 Stéphane Rondinaud
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

require 'version_synthesis'

class MyRoadmapsController < ApplicationController
  unloadable
  before_filter :authorize_my_roadmaps 

  helper :queries
  include QueriesHelper
  def index

    get_query

    @user_synthesis = Hash.new

    if @query.has_filter?('tracker_id')
      tracker_list = Tracker.find(:all, :conditions => [@query.statement_for('tracker_id').gsub('issues.tracker_id','trackers.id')+' and is_in_roadmap = ?',1], :order => 'position')
    else 
      tracker_list = Tracker.find(:all, :conditions => ['is_in_roadmap = ?', 1], :order => 'position')
    end

    # condition hacked from the Query model to match versions
    version_condition = '(versions.status <> \'closed\')'
    version_condition += ' and ('+@query.statement_for('project_id').gsub('issues','versions')+' or exists (select 1 from issues where issues.fixed_version_id = versions.id and '+@query.statement_for('project_id')+'))' if @query.has_filter?('project_id')

    Version.find(:all, :conditions => [version_condition] ) \
    .select{|version| !version.completed? } \
    .each{|version|
      issue_condition = ''
      issue_condition += @query.statement_for('project_id')+' and ' unless @query.statement_for('project_id').nil? 
      issue_condition += 'tracker_id in (?) and '+ \
        '( fixed_version_id = ? '+ \
        'or exists (select 1 '+ \
        'from issues as subissues '+ \
        'where issues.root_id = subissues.root_id '+ \
        'and subissues.fixed_version_id = ?) )'

      issue_condition = [issue_condition, tracker_list, version.id, version.id]

      grouped_issues = Hash.new
      Issue.visible.find(:all, :conditions => issue_condition, :include => [:status,:tracker], :order => 'project_id,tracker_id' ) \
      .each {|issue|
        if grouped_issues[issue.project].nil?
          grouped_issues[issue.project]=[issue]
        else
          grouped_issues[issue.project].push(issue)
        end
      }
      
      grouped_issues.each{|project, issues|
        if @user_synthesis[project].nil?
          @user_synthesis[project] = Hash.new
        end
        if @user_synthesis[project][version].nil?
          @user_synthesis[project][version] = VersionSynthesis.new(project, version, issues)
        else
          @user_synthesis[project][version].add_issues(issues)
        end
      }
    }
  end
  
  def initialize
    index=0
    @tracker_styles = Hash.new
    Tracker.find(:all, :conditions => ['is_in_roadmap = ?', 1], :order => 'position' ).each{ |tracker|
      @tracker_styles[tracker]=Hash.new
      @tracker_styles[tracker][:opened] = "t"+(index%10).to_s+"_opened"
      @tracker_styles[tracker][:done] = "t"+(index%10).to_s+"_done"
      @tracker_styles[tracker][:closed] = "t"+(index%10).to_s+"_closed"
      index += 1
    }
  end
  
  private
  
  def authorize_my_roadmaps
    if !(User.current.allowed_to?(:view_my_roadmaps, nil, :global => true) || User.current.admin?)
      render_403
      return false
    end
    return true
  end
  
  def get_query
    @query = Query.new(:name => "_", :filters => {})
    user_projects = Project.visible
    user_trackers = Tracker.find(:all, :conditions => ['is_in_roadmap = ?', 1])
    filters = Hash.new
    filters['project_id'] = { :type => :list_optional, :order => 1, :values => user_projects.sort{|a,b| a.self_and_ancestors.join('/')<=>b.self_and_ancestors.join('/') }.collect{|s| [s.self_and_ancestors.join('/'), s.id.to_s] } } unless user_projects.empty?
    filters['tracker_id'] = { :type => :list, :order => 2, :values => Tracker.find(:all, :conditions => ['is_in_roadmap = ?', 1], :order => 'position' ).collect{|s| [s.name, s.id.to_s] } } unless user_trackers.empty?
    @query.override_available_filters(filters)
    if params[:f]
      build_query_from_params
    end
    @query.filters={ 'project_id' => {:operator => "*", :values => [""]} } if @query.filters.length==0
  end

  # backported from redmine 1.3 queries_helper.rb
  def build_query_from_params
    if params[:fields] || params[:f]
      @query.filters = {}
      @query.add_filters(params[:fields] || params[:f], params[:operators] || params[:op], params[:values] || params[:v])
    else
      @query.available_filters.keys.each do |field|
        @query.add_short_filter(field, params[field]) if params[field]
      end
    end
    @query.group_by = params[:group_by] || (params[:query] && params[:query][:group_by])
    @query.column_names = params[:c] || (params[:query] && params[:query][:column_names])
  end
end
