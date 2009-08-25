class TimerSchema1 < ActiveRecord::Migration
  def self.up
    create_table :once_events do |t|
      t.string :to
      t.binary :data
      t.binary :options
      t.boolean :ack
      t.integer :retry
      t.integer :event_time
    end
    
    add_index :once_events, :event_time
    
    create_table :periodic_events do |t|
      t.string :to
      t.binary :data
      t.binary :options
      t.boolean :ack
      t.integer :retry
      t.integer :event_time
    end
    
    add_index :periodic_events, :event_time
  end

  def self.down
  end
end
