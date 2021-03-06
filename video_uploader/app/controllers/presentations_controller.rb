class PresentationsController < ApplicationController
  before_action :authenticate_admin!
  before_action :fetch_playlists, only: [:new]

  def index
    @current_page = (params[:page] || 1).to_i
    @presentations = Presentation.active.order('created_at DESC').page(@current_page)
    @total_records = @presentations.total_count
  end

  def new
    if params[:event_id].present?
      @event = Event.find(params[:event_id])
      @presentation = Presentation.new(
                                      event: @event,
                                      title: @event.title,
                                      description: @event.description,
                                      presented_at: @event.event_date,
                                      playlist_id: ENV['DEFAULT_PLAYLIST_ID']
      )
    else
      @presentation = Presentation.new(
          description: "Speaker: \n\nEvent Page: \n\nProduced by Engineers.SG",
          presented_at: Date.today,
          playlist_id: ENV['DEFAULT_PLAYLIST_ID']
      )
    end
  end

  def create
    if params[:presentation_id].present?
      @presentation = Presentation.find(params[:presentation_id])
    else
      @presentation = Presentation.create(presentation_params)
    end

    unless @presentation.valid?
      return render json: {status: 'failed_to_save', error: @presentation.errors.messages}, status: 500
    end

    if params[:file].present?
      saved_file_path, md5_filename = move_uploaded_file(file_params)

      if saved_file_path.present? && File.exist?(saved_file_path)
        @presentation.update(status: 'uploaded', uploaded_file: md5_filename)

        Rails.logger.info "Adding ProcessVideoWorker for #{saved_file_path}"
        ProcessVideoWorker.perform_async(@presentation.id)
      end
    end

    render json: {status: 'success'}
  end

  def destroy
    presentation = Presentation.find(params[:id])
    presentation.update(active: false)

    redirect_to presentations_path, notice: "\"#{presentation.title}\" was marked as hidden."
  end

  def edit
    @presentation = Presentation.find(params[:id])
  end

  def update
    @presentation = Presentation.find(params[:id])
    @presentation.update(presentation_params)

    if @presentation.valid?
      if (@presentation.has_video_link?)
        begin
          youtube_service = YoutubeService.new
          options = {
              id: @presentation.video_id,
              title: @presentation.title,
              description: @presentation.description,
          }
          api_response = youtube_service.update_video(options)

          Rails.logger.info("Video id '#{api_response.try(:data).try(:id)}' was successfully updated.")
        rescue => e
          Rails.logger.error("Failed to update YouTube (#{@presentation.video_id}): #{e.message}")
        end
      end

      redirect_to presentations_path, notice: "\"#{@presentation.title}\" was updated."
    else
      flash.now[:error] = 'Unable to update this presentation: ' + @presentation.errors.messages
      render :edit
    end
  end

  private

  def presentation_params
    params.permit(:title, :description, :presented_at, :event_id, :playlist_id)
  end

  def file_params
    params.require(:file)
  end

  def move_uploaded_file(uploaded_file={})
    return if uploaded_file == nil

    if uploaded_file.try(:original_filename)
      md5_filename = Digest::MD5.hexdigest("#{uploaded_file.original_filename}-#{Time.now.to_i}")
      file_ext = File.extname(uploaded_file.original_filename)
      temp_file = uploaded_file.tempfile
    else
      md5_filename = Digest::MD5.hexdigest("#{uploaded_file[:original_filename]}-#{Time.now.to_i}")
      file_ext = File.extname(uploaded_file[:original_filename])
      temp_file = uploaded_file[:tempfile]
    end

    save_path = File.join(ENV['UPLOAD_FOLDER'], md5_filename, md5_filename + file_ext)

    dir = File.dirname(save_path.to_s)
    FileUtils.mkdir_p(dir, mode: 0777) unless File.directory?(dir)

    if File.exist?(temp_file)
      Rails.logger.info "Copying #{temp_file} to #{save_path}..."
      FileUtils.mv(temp_file, save_path)

      [save_path, md5_filename]
    end
  end

  def fetch_playlists
    @playlists ||= Playlist.active.order('title ASC')
  end
end
