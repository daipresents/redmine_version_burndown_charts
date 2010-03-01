class VersionBurndownChartsController < ApplicationController
  unloadable
  menu_item :version_burndown_charts
  before_filter :find_project, :find_version, :find_version_issues, :find_burndown_dates, :find_version_info, :find_issues_closed_status
  
  def index
    relative_url_path =
      ActionController::Base.respond_to?(:relative_url_root) ? ActionController::Base.relative_url_root : ActionController::AbstractRequest.relative_url_root

    @graph =
      open_flash_chart_object( 880, 450,
        url_for( :action => 'get_graph_data', :project_id => @project.id, :version_id => @version.id ),
          true, "#{relative_url_path}/" )
  end

  def get_graph_data
    
    estimated_data_array = []
    performance_data_array = []
    x_labels_data = []
    
    index_date = @start_date - 1
    index_estimated_hours = @estimated_hours
    index_performance_hours = @estimated_hours
    count = 1
    
    while index_date <= (@version.due_date + 1)
      logger.debug("index_date #{index_date}")

      if index_date < @start_date
        # ready
        estimated_data_array << index_estimated_hours
        performance_data_array << index_performance_hours
        index_date += 1
        count += 1
        next
      elsif index_date == @start_date || index_date == @version.due_date
        x_labels_data << index_date.strftime("%m/%d")
      elsif @sprint_range > 20 && count % (@sprint_range / 3).round != 0
         x_labels_data << ""
      else
        x_labels_data << index_date.strftime("%m/%d")
      end
      
      estimated_data_array << round(index_estimated_hours -= calc_estimated_hours_by_date(index_date))
      performance_data_array << round(index_performance_hours -= calc_performance_hours_by_date(index_date))
      
      logger.debug("#{index_date} index_estimated_hours #{round(index_estimated_hours)}")
      logger.debug("#{index_date} index_performance_hours #{round(index_performance_hours)}")
      
      index_date += 1
      count += 1
    end

    create_graph(x_labels_data, estimated_data_array, performance_data_array)
  end

  def create_graph(x_labels_data, estimated_data_array, performance_data_array)
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
    y.set_range(0, @estimated_hours + 1, (@estimated_hours / 4).round)
    chart.y_axis = y

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

    render :text => chart.to_s
  end
  
  def calc_estimated_hours_by_date(target_date)
    target_issues = @version_issues.select { |issue| issue.due_date == target_date}
    target_hours = 0
    target_issues.each do |issue|
      target_hours += round(issue.estimated_hours)
    end
    logger.debug("#{target_date} estimated hours = #{target_hours}")
    return target_hours
  end

  def calc_performance_hours_by_date(target_date)
    target_hours = 0
    @version_issues.each do |issue|
      journals = issue.journals.select {|journal| journal.created_on.to_date == target_date}
      next if journals.empty?
      
      journal_details =
        journals.map(&:details).flatten.select {|detail| 'status_id' == detail.prop_key}
      next if journal_details.empty?
      
      journal_details.each do |journal_detail|
        logger.debug("journal_detail id #{journal_detail.id}")
        @closed_statuses.each do |closed_status|
          logger.debug("closed_status id #{closed_status.id}")
          if journal_detail.value.to_i == closed_status.id
            logger.debug("#{target_date} issue.estimated_hours #{issue.estimated_hours} id #{issue.id}")
            target_hours += round(issue.estimated_hours)
          end
        end
      end
    end
    logger.debug("issues estimated hours #{target_hours} #{target_date}")
    return target_hours
  end

  def round(value)
    unless value
      return 0
    else
      return (value.to_f * 10.0).round / 10.0
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

    unless @version.due_date
      flash[:error] = l(:version_burndown_charts_version_due_date_not_found)
      render :action => "index" and return false
    end
  end

  def find_version_issues
    @version_issues = Issue.find_by_sql([
          "select * from issues
             where fixed_version_id = :version_id and start_date is not NULL and
               estimated_hours is not NULL order by start_date asc",
                 {:version_id => @version.id}])
    if @version_issues.empty?
      flash[:error] = l(:version_burndown_charts_issues_not_found)
      render :action => "index" and return false
    end
  end

  def find_burndown_dates
    @start_date = @version_issues[0].start_date
    if @version.due_date <= @start_date
      flash[:error] = l(:version_burndown_charts_version_start_date_invalid)
      render :action => "index" and return false
    end

    @sprint_range = @version.due_date - @start_date + 1

    logger.debug("@start_date #{@start_date}")
    logger.debug("@version.due_date #{@version.due_date}")
    logger.debug("@sprint_range = #{@sprint_range}")
  end

  def find_version_info
    @closed_pourcent = (@version.closed_pourcent * 100).round / 100
    @open_pourcent = 100 - @closed_pourcent
    unless @version.estimated_hours
      flash[:error] = l(:version_burndown_charts_issues_start_date_or_estimated_date_not_found)
      render :action => "index" and return false
    end
    @estimated_hours = round(@version.estimated_hours)
    logger.debug("@estimated_hours #{@estimated_hours}")
  end

  def find_issues_closed_status
    @closed_statuses = IssueStatus.find_all_by_is_closed(1)
    logger.debug("@closed_statuses #{@closed_statuses}")
  end
end
