class VersionBurndownChartsController < ApplicationController
  unloadable
  menu_item :version_burndown_charts
  before_filter :find_project, :find_version
  
  def index
    @graph = open_flash_chart_object( 850, 450, url_for( :action => 'get_graph_data', :project_id => @project.id, :version_id => @version.id ) )
  end

  def get_graph_data

    @version_issues = Issue.find_by_sql([
          "select * from issues
            where fixed_version_id = :version_id and start_date is not NULL order by start_date asc",
            {:version_id => @version.id}])

    @version_issues_time_entries = []
    @version_issues.each do |issue|
      entries = TimeEntry.find_all_by_issue_id(issue.id)
      if entries
        @version_issues_time_entries = @version_issues_time_entries.concat(entries)
      end
    end

    # time entry date invalid. default value setting.
    @start_date = @version_issues[0].start_date - 1
    if !@version_issues_time_entries.empty?
      @version_issues_time_entries = @version_issues_time_entries.sort{|aa, bb| aa.spent_on <=> bb.spent_on}
    end

    logger.debug("@start_date #{@start_date}")
    @sprint_range = @version.due_date - @start_date + 1
    logger.debug("@sprint_range = #{@sprint_range}")
    @closed_pourcent = (@version.closed_pourcent * 100).round / 100
    @open_pourcent = 100 - @closed_pourcent

    @closed_statuses = IssueStatus.find_all_by_is_closed(1)
    
    logger.debug("@version.estimated_hours #{@version.estimated_hours}")

    perfect_data_array = []
    perfect_data_array << @version.estimated_hours
    perfect_daily_hours = @version.estimated_hours / @sprint_range.to_f
    logger.debug("perfect_daily_hours = #{perfect_daily_hours}")
    
    estimated_data_array = []
    estimated_data_array << @version.estimated_hours

    performance_data_array = []
    performance_data_array << @version.estimated_hours

    #spent_data_array = []
    #spent_data_array << @version.estimated_hours

    index_date = @start_date
    index_perfect_hours = @version.estimated_hours
    index_estimated_hours = @version.estimated_hours
    index_performance_hours = @version.estimated_hours
    #index_spend_hours = @version.estimated_hours
    count = 1
    x_labels_data = []
    x_labels_data << ""
    
    while index_date <= @version.due_date
      index_perfect_hours -= perfect_daily_hours
      if index_perfect_hours > 0
        perfect_data_array << index_perfect_hours
      else
        perfect_data_array << 0
      end
      
      estimated_hours = calc_estimated_hours_by_date(index_date)
      estimated_data_array << index_estimated_hours -= estimated_hours
      logger.debug("estimated_hours #{estimated_hours}")
      
      performance_hours = calc_performance_hours_by_date(index_date)
      performance_data_array << index_performance_hours
      logger.debug("performance_hours #{performance_hours}")
      
      #spent_hours = calc_spent_hours_by_date(index_date)
      #index_spend_hours -= spent_hours
      #if index_spend_hours > 0
      #  spent_data_array << index_spend_hours
      #else
      #  spent_data_array << 0
      #end
      #logger.debug("spent_hours #{spent_hours}")
      
      logger.debug("index_perfect_hours #{index_perfect_hours}")
      logger.debug("index_estimated_hours #{index_estimated_hours}")
      logger.debug("index_performance_hours #{index_performance_hours}")
      #logger.debug("index_spend_hours #{index_spend_hours}")

      if @sprint_range > 20
        # x label date per 3days.
        if count == 1 || count % 3 == 0
          x_labels_data << index_date.strftime("%m/%d")
        else
          x_labels_data << " "
        end
      else
        x_labels_data << index_date.strftime("%m/%d")
      end
      
      index_date += 1
      count += 1
    end

    chart =OpenFlashChart.new
    chart.set_title(Title.new("#{@version.name} #{l(:version_burndown_charts)}"))
    chart.set_bg_colour('#ffffff');

    x_legend = XLegend.new("#{l(:version_burndown_charts_xlegend)}")
    x_legend.set_style('{font-size: 20px; color: #000000}')
    chart.set_x_legend(x_legend)

    y_legend = YLegend.new("#{l(:version_burndown_charts_ylegend)}")
    y_legend.set_style('{font-size: 20px; color: #000000}')
    chart.set_y_legend(y_legend)

    x = XAxis.new
    x.set_range(0, @sprint_range + 2, 1)
    x.set_labels(x_labels_data)
    chart.x_axis = x

    y = YAxis.new
    y.set_range(0, @version.estimated_hours + 1, (@version.estimated_hours / 4).round)
    chart.y_axis = y

    if perfect_daily_hours >= 1
      perfect_line = Line.new
      perfect_line.text = "#{l(:version_burndown_charts_perfect_line)}"
      perfect_line.width = 2
      perfect_line.colour = '#d3d3d3'
      perfect_line.values = perfect_data_array
      chart.add_element(perfect_line)
    end

    estimated_line = LineDot.new
    estimated_line.text = "#{l(:version_burndown_charts_estimated_line)}"
    estimated_line.width = 2
    estimated_line.colour = '#00a497'
    estimated_line.dot_size = 4
    estimated_line.values = estimated_data_array
    chart.add_element(estimated_line)

    performance_line = LineDot.new
    performance_line.text = "#{l(:version_burndown_charts_peformance_line)}"
    performance_line.width = 3
    performance_line.colour = '#bf0000'
    performance_line.dot_size = 6
    performance_line.values = performance_data_array
    chart.add_element(performance_line)

    #spent_line = Line.new
    #spent_line.text = "#{l(:version_burndown_charts_spent_line)}"
    #spent_line.width = 2
    #spent_line.colour = '#e6b422'
    #spent_line.values = spent_data_array
    #chart.add_element(spent_line)
    
    render :text => chart.to_s
  end

  def calc_estimated_hours_by_date(target_date)
    target_issues = @version_issues.select { |issue| issue.due_date == target_date}
    target_hours = 0
    target_issues.each do |issue|
      target_hours += issue.estimated_hours
    end
    logger.debug("#{target_date} estimated hours = #{target_hours}")
    return target_hours
  end

  def calc_performance_hours_by_date(target_date)
    target_issues = @version_issues.select { |issue| issue.due_date == target_date}
    if target_issues
      target_issues = target_issues.select { |issue| issue.closed? }
      target_hours = 0
      target_issues.each do | issue |
        logger.debug("issue status #{issue.status_id}")
        target_hours += issue.estimated_hours
      end
      return target_hours
    else
      return 0
    end
  end

  def calc_spent_hours_by_date(target_date)
    target_time_entries = @version_issues_time_entries.select { |time_entry| time_entry.spent_on == target_date }
    if target_time_entries
      target_hours = 0
      target_time_entries.each do |target_time_entry|
          target_hours += target_time_entry.hours
      end
      logger.debug("#{target_date} spent hours = #{target_hours}")
      return target_hours
    else
      return 0
    end
  end

  def find_project
    render_error(l(:version_burndown_charts_project_nod_found)) and return unless params[:project_id]
    @project = Project.find(params[:project_id])
    render_error(l(:version_burndown_charts_project_nod_found)) and return unless @project
  end

  def find_version
    if params[:version_id]
      @version = Version.find(params[:version_id])
    else
      # First display case.
      @version = @project.current_version
    end
    render_error(l(:version_burndown_charts_version_not_found)) and return unless @version
    render_error(l(:version_burndown_charts_version_due_date_not_found)) and return unless @version.due_date
    render_error(l(:version_burndown_charts_version_estimated_hours_not_found)) and return unless @version.estimated_hours
    render_error(l(:version_burndown_charts_issues_not_found)) and return if @version.issues_count == 0
  end
end
