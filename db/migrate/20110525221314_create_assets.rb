class CreateAssets < ActiveRecord::Migration
  def change
    create_table :assets do |t|
      t.string :url
      t.string :checksum
      t.string :type
      t.timestamps
    end
  end
end
