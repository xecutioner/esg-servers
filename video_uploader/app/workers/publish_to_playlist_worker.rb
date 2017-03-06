class PublishToPlaylistWorker
  include Sidekiq::Worker
  sidekiq_options queue: :publishing

  def perform(presentation_id, play_list_id, video_id)
    presentation = Presentation.find(presentation_id)
    presentation.update(status: 'adding_to_playlist')

    begin
      puts "Publishing video(#{video_id}) to playlist(#{play_list_id})"

      YoutubeService.new.add_to_playlist(playlist_id: play_list_id, video_id: video_id)
      presentation.update(status: 'added_to_playlist')
    rescue Google::APIClient::TransmissionError => e
      presentation.update(status: 'failed_to_add_to_playlist')
      puts e.result.body
    end
  end
end
