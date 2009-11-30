module ASS
  module JSON
    require 'json'
    def self.load(raw)
      JSON.parse(raw)
    end

    def self.dump(obj)
      obj.to_json
    end
  end

  module Marshal
    def self.load(raw)
      ::Marshal.load(raw)
    end

    def self.dump(obj)
      ::Marshal.dump(obj)
    end
  end

  # mongodb BSON
  module BSON
  end
end
