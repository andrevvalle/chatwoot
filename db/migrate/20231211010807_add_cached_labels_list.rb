class AddCachedLabelsList < ActiveRecord::Migration[7.0]
  def change
    add_column :conversations, :cached_label_list, :string
    Conversation.reset_column_information
    # ActsAsTaggableOn::Taggable::Cache.included(Conversation)
    # Commented out due to compatibility with newer acts-as-taggable-on version
  end
end
