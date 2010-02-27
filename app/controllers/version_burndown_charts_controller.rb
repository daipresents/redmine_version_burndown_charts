class VersionBurndownChartsController < ApplicationController
  unloadable
  menu_item :version_burndown_charts
  before_filter :initialize_burndown

  def index
    @graph = open_flash_chart_object( 800, 450, url_for( :action => 'get_graph_data', :project_id => @project.id, :version_id => @version.id ) )
  end

  def get_graph_data

    start_date = @version_issues[0].start_date
    @sprint_date = @version.due_date - start_date

    estimated_data_array = []
    estimated_data_array << @version.estimated_hours
    
    spent_data_array = []
    spent_data_array << @version.estimated_hours

    index_date = start_date
    index_estimated_hours = @version.estimated_hours
    estimated_daily_hours = ((@version.estimated_hours / @sprint_date) * 100).round / 100
    
    while index_date <= @version.due_date
      estimated_data_array << index_estimated_hours - estimated_daily_hours

      spent_data_array << index_estimated_hours - calc_spent_hours_by_date(index_date)

      index_estimated_hours -= estimated_daily_hours
      index_date += 1
    end

    line_dot = LineDot.new
    line_dot.text = "#{l(:version_burndown_charts_spent_line)}"
    line_dot.width = 4
    line_dot.colour = '#bf0000'
    line_dot.dot_size = 5
    line_dot.values = spent_data_array

    line = Line.new
    line.text = "#{l(:version_burndown_charts_estimated_line)}"
    line.width = 1
    line.colour = '#5E4725'
    line.dot_size = 5
    line.values = estimated_data_array

    x_legend = XLegend.new("#{l(:version_burndown_charts_xlegend)}")
    x_legend.set_style('{font-size: 20px; color: #778877}')

    y_legend = YLegend.new("#{l(:version_burndown_charts_ylegend)}")
    y_legend.set_style('{font-size: 20px; color: #770077}')

    y = YAxis.new
    y.set_range(0, @version.estimated_hours + 20, 20)

    chart =OpenFlashChart.new
    chart.set_title(Title.new("#{@version.name} #{l(:version_burndown_charts)}"))
    chart.set_x_legend(x_legend)
    chart.set_y_legend(y_legend)
    chart.y_axis = y
    chart.add_element(line_dot)
    chart.add_element(line)

    render :text => chart.to_s
  end

  def calc_spent_hours_by_date(target_date)
    target_time_entries = @version_issues_time_entries.select { |time_entry| time_entry.spent_on = target_date }
    if target_time_entries
      return 0
    else
      return target_time_entries.sum(:hours)
    end
  end

  def initialize_burndown
    render_error(l(:version_burndown_charts_project_nod_found)) and return unless params[:project_id]

    @project = Project.find(params[:project_id])
    render_error(l(:version_burndown_charts_project_nod_found)) and return unless @project

    if params[:version_id]
      @version = Version.find(params[:version_id])
    else
      # First display case.
      @version = @project.current_version
    end
    render_error(l(:version_burndown_charts_version_not_found)) and return unless @version

    @version_issues = Issue.find_by_sql([
          "select * from issues
            where fixed_version_id = :version_id and start_date is not NULL order by start_date asc",
            {:version_id => @version.id}])
    render_error(l(:version_burndown_charts_issues_not_found)) and return unless @version_issues.empty?

    @version_issues_time_entries = []
    @version_issues.each do |issue|
      entries = TimeEntry.find_all_by_issue_id(issue.id)
      logger.debug(entries)

      if entries
        logger.debug("add time entries.")
        @version_issues_time_entries = @version_issues_time_entries.concat(entries)
      end
    end

    render_error(l(:version_burndown_charts_time_entries_not_found)) and return if @version_issues_time_entries.empty?

  end

  def find_version_data
    @version_issue_count = @version.issue_count
    @version_open_issues_count = @version.open_issues_count
    @version_closed_issues_count = @version.closed_issues_count

    @start_date
    @due_date = @version.due_date
    @spent_hours = @version.spent_hours
    @total_hours = @version.estimated_hours
  end
end
