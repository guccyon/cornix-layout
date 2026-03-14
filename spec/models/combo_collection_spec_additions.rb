require_relative '../spec_helper'
require_relative '../../lib/cornix/models/combo'
require_relative '../../lib/cornix/models/combo_collection'
require_relative '../../lib/cornix/models/macro'
require_relative '../../lib/cornix/models/macro_collection'

RSpec.describe Cornix::Models::ComboCollection do
  describe 'index validation' do
    it '重複するindexを持つComboがある場合にエラー' do
      combo1 = Cornix::Models::Combo.new(
        index: 0, name: 'Combo1', description: '',
        trigger_keys: ['A', 'B'], output_key: 'C'
      )
      combo2 = Cornix::Models::Combo.new(
        index: 0, name: 'Combo2', description: '',  # 同じindex
        trigger_keys: ['D', 'E'], output_key: 'F'
      )

      collection = described_class.new([combo1, combo2])
      errors = collection.structural_errors

      expect(errors).not_to be_empty
      expect(errors.join).to include('Duplicate')
      expect(errors.join).to include('indices')
    end
  end
end

RSpec.describe Cornix::Models::MacroCollection do
  describe 'index validation' do
    it '重複するindexを持つMacroがある場合にエラー' do
      macro1 = Cornix::Models::Macro.new(
        index: 0, name: 'Macro1', description: '',
        sequence: [Cornix::Models::Macro::MacroStep.new(action: 'tap', keys: ['A'])]
      )
      macro2 = Cornix::Models::Macro.new(
        index: 0, name: 'Macro2', description: '',  # 同じindex
        sequence: [Cornix::Models::Macro::MacroStep.new(action: 'tap', keys: ['B'])]
      )

      collection = described_class.new([macro1, macro2])
      errors = collection.structural_errors

      expect(errors).not_to be_empty
      expect(errors.join).to include('Duplicate')
      expect(errors.join).to include('indices')
    end
  end
end
