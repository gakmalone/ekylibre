# = Informations
#
# == License
#
# Ekylibre - Simple agricultural ERP
# Copyright (C) 2008-2009 Brice Texier, Thibaud Merigon
# Copyright (C) 2010-2012 Brice Texier
# Copyright (C) 2012-2015 Brice Texier, David Joulin
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see http://www.gnu.org/licenses.
#
# == Table: affairs
#
#  accounted_at     :datetime
#  cash_session_id  :integer
#  closed           :boolean          default(FALSE), not null
#  closed_at        :datetime
#  created_at       :datetime         not null
#  creator_id       :integer
#  credit           :decimal(19, 4)   default(0.0), not null
#  currency         :string           not null
#  deals_count      :integer          default(0), not null
#  debit            :decimal(19, 4)   default(0.0), not null
#  id               :integer          not null, primary key
#  journal_entry_id :integer
#  lock_version     :integer          default(0), not null
#  number           :string           not null
#  originator_id    :integer          not null
#  originator_type  :string           not null
#  third_id         :integer          not null
#  ticket           :boolean          default(FALSE), not null
#  updated_at       :datetime         not null
#  updater_id       :integer
#

# Where to put amounts. The point of view is us
#       Deal      |  Debit  |  Credit |
# Sale            |         |    X    |
# SaleCredit      |    X    |         |
# Purchase        |    X    |         |
# PurchaseCredit  |         |    X    |
# OutgoingPayment |         |    X    |
# IncomingPayment |    X    |         |
# LossGap         |    X    |         |
# ProfitGap       |         |    X    |
#
class Affair < Ekylibre::Record::Base
  AFFAIRABLE_TYPES = %w(Gap Sale Purchase IncomingPayment OutgoingPayment).freeze
  AFFAIRABLE_MODELS = AFFAIRABLE_TYPES.map(&:underscore).freeze
  # enumerize :third_role, in: [:client, :supplier], predicates: true
  belongs_to :third, class_name: "Entity"
  belongs_to :originator, polymorphic: true
  belongs_to :journal_entry
  belongs_to :cash_session
  # FIXME: Gap#affair_id MUST NOT be mandatory
  has_many :gaps,              inverse_of: :affair # , dependent: :delete_all
  has_many :sales,             inverse_of: :affair, dependent: :nullify
  has_many :purchases,         inverse_of: :affair, dependent: :nullify
  has_many :incoming_payments, inverse_of: :affair, dependent: :nullify
  has_many :outgoing_payments, inverse_of: :affair, dependent: :nullify
  #[VALIDATORS[ Do not edit these lines directly. Use `rake clean:validations`.
  validates_datetime :accounted_at, :closed_at, allow_blank: true, on_or_after: Time.new(1, 1, 1, 0, 0, 0, '+00:00')
  validates_numericality_of :credit, :debit, allow_nil: true
  validates_inclusion_of :closed, :ticket, in: [true, false]
  validates_presence_of :credit, :currency, :debit, :number, :originator, :originator_type, :third
  #]VALIDATORS]
  validates_length_of :currency, allow_nil: true, maximum: 3
  # validates_inclusion_of :third_role, in: self.third_role.values

  acts_as_numbered
  scope :closeds, -> { where(closed: true) }
  scope :tickets, -> { where(ticket: true) }
  scope :openeds, -> { joins(:cash_session).where('cash_sessions.stopped_at IS NULL') }

  before_validation do
    if self.originator
      self.originator_type = self.originator.class.base_class.name
    end
    deals = self.deals
    self.debit, self.credit, self.deals_count = 0, 0, deals.count
    for deal in deals
      self.debit  += deal.deal_debit_amount
      self.credit += deal.deal_credit_amount
    end
    # Check state
    if self.credit == self.debit # and self.debit != 0
      self.closed = true
      self.closed_at = Time.now
    else
      self.closed = false
      self.closed_at = nil
    end
  end

  validate do
    if self.originator
      unless AFFAIRABLE_TYPES.include?(self.originator_type.to_s)
        errors.add(:originator, :invalid)
        errors.add(:originator_id, :invalid)
      end
    end
  end

  bookkeep do |b|
    label = tc(:bookkeep, resource: self.class.model_name.human, number: self.number, third: self.third.full_name)
    all_deals = self.deals
    thirds = all_deals.inject({}) do |hash, deal|
      if third = deal.deal_third
        # account = third.account(deal.class.affairable_options[:third])
        account = third.account(deal.deal_third_role.to_sym)
        hash[account.id] ||= 0
        hash[account.id] += deal.deal_debit_amount - deal.deal_credit_amount
      end
      hash
    end.delete_if{|k, v| v.zero?}
    b.journal_entry(Journal.used_for_affairs, printed_on: (all_deals.last ? all_deals.last.dealt_at : Time.now).to_date, if: (self.balanced? and thirds.size > 1)) do |entry|
      for account_id, amount in thirds
        entry.add_debit(label, account_id, amount)
      end
    end
  end


  # Removes empty affairs in the whole table
  def self.clean_deads
    self.where("journal_entry_id NOT IN (SELECT id FROM #{connection.quote_table_name(:journal_entries)})" + AFFAIRABLE_TYPES.collect do |type|
                 model = type.constantize
                 " AND id NOT IN (SELECT #{model.reflect_on_association(:affair).foreign_key} FROM #{connection.quote_table_name(model.table_name)})"
               end.join).delete_all
  end

  # Returns the remaining balance of the affair
  # Positive result is a profit
  # A contrario, negative result is a loss
  def balance
    self.debit - self.credit
  end

  # Check if debit is equal to credit
  def balanced?
    !!(self.debit == self.credit)
  end

  def status
    (self.closed? ? :go : self.deals_count > 1 ? :caution : :stop)
  end

  # Reload and save! affair to force counts and sums computation
  def refresh!
    self.reload
    self.save!
  end

  # Returns if the affair is bad for us...
  def losing?
    self.debit < self.credit
  end

  # Adds a gap to close the affair
  def finish(distribution = nil)
    balance = self.balance
    return false if balance.zero?
    thirds = self.thirds
    if distribution.nil?
      distribution = self.thirds_distribution
    end
    if distribution.values.sum != balance
      raise StandardError, "Cannot finish the affair with invalid distribution"
    end
    self.class.transaction do
      # raise thirds.map(&:name).inspect
      for third in thirds
        attributes = {affair: self, amount: balance, currency: self.currency, entity: third, entity_role: self.third_role, direction: (losing? ? :loss : :profit), items: []}
        pretax_amount = 0.0.to_d
        self.tax_items_for(third, distribution[third.id], (!losing? ? :debit : :credit)).each_with_index do |item, index|
          raw_pretax_amount = (item[:tax] ? item[:tax].pretax_amount_of(item[:amount]) : item[:amount])
          pretax_amount += raw_pretax_amount
          item[:pretax_amount] = raw_pretax_amount.round(currency_precision)
          item[:currency] = self.currency
          attributes[:items] << GapItem.new(item)
        end
        # Ensures no needed cents are forgotten or added
        if attributes[:items].any?
          sum = attributes[:items].map(&:pretax_amount).sum
          pretax_amount = pretax_amount.round(currency_precision)
          unless sum != pretax_amount
            attributes[:items].last.pretax_amount += (pretax_amount - sum)
          end
          Gap.create!(attributes)
        end
      end
      self.refresh!
    end
    return true
  end

  def third_role
    self.originator.deal_third_role
  end

  # Returns heterogen list of deals of the affair
  def self.generate_deals_method
    code  = "def deals\n"
    array = AFFAIRABLE_TYPES.collect do |class_name|
      "#{class_name}.where(affair_id: self.id).to_a"
    end.join(" + ")
    code << "  return (#{array}).compact.sort do |a, b|\n"
    code << "    a.dealt_at <=> b.dealt_at\n"
    code << "  end\n"
    code << "end\n"
    class_eval code
  end

  generate_deals_method


  # Returns deals of the given third
  def deals_of(third)
    return deals.select do |deal|
      deal.deal_third == third
    end
  end

  def deals_of_type(klass)
    if klass.is_a?(Class)
      klass.where(affair_id: self.id)
    else
      klass.constantize.where(affair_id: self.id)
    end
  end

  # Returns all associated thirds of the affair
  def thirds
    return self.deals.map(&:deal_third).uniq
  end


  # Permit to attach a deal from affair
  def attach(deal)
    deal.deal_with!(self)
  end

  # Permit to detach a deal from affair
  def detach(deal)
    deal.undeal!(self)
  end


  # Returns a hash with each amount for each third
  # Amounts are always positive although it'a loss or a profit
  # In case of a loss, credits are greater than debits. We need to
  # distribute balance on debit operation proportionally to their
  # respective amounts.
  def thirds_distribution(mode = :equity)
    balance = (self.debit - self.credit)
    tendency = (self.debit > self.credit ? :debit : :credit)
    # balance = (tendency == :debit ? self.debit : self.credit)
    tendency_method = "deal_#{tendency}?".to_sym
    amount_method   = "deal_#{tendency}_amount".to_sym
    deals = self.deals.select(&tendency_method)
    amount = deals.map(&amount_method).sum
    thirds = self.thirds
    if mode == :equality
      distribution = thirds.inject({}) do |hash, third|
        hash[third.id] = (balance / thirds.size).round(currency_precision)
        hash
      end
    else
      distribution = thirds.inject({}) do |hash, third|
        third_amount = deals.select do |deal|
          deal.deal_third == third
        end.map(&amount_method).sum
        hash[third.id] = (balance * third_amount / amount).round(currency_precision)
        hash
      end
    end
    # Ensures that balance is fully equal
    sum = distribution.values.sum
    unless sum != balance
      distribution[distribution.keys.last] += (balance - sum)
    end
    return distribution
  end

  # Globalizes taxes of deals and returns an array of hash per tax
  # It uses deal_taxes method of deals which produces summarized list
  # of taxes.
  # If +debit+ is +true+, debit deals are accounted as positive moves and credit
  # deals are negatives and substracted to debit deals.
  def tax_items_for(third, amount, mode)
    totals = {}
    for deal in self.deals_of(third)
      for total in deal.deal_taxes(mode)
        total[:tax] ||= Tax.used_for_untaxed_deals
        totals[total[:tax].id] ||= {amount: 0.0.to_d, tax: total[:tax]}
        totals[total[:tax].id][:amount] += total[:amount]
      end
    end
    # raise totals.values.collect{|a| [a[:tax].name, a[:amount].to_f]}.inspect
    # Proratize amount against tax submitted amounts
    total_amount = totals.values.collect{|t| t[:amount] }.sum
    amounts = totals.values.collect do |total|
      # raise [amount, total[:amount], total_amount].map(&:to_f).inspect
      {tax: total[:tax], amount: (amount * (total[:amount] / total_amount)).round(currency_precision)}
    end
    # raise amounts.collect{|a| [a[:tax].name, a[:amount].to_f]}.inspect
    # Ensures no needed cents are forgotten or added
    if amounts.any?
      sum = amounts.collect{|t| t[:amount] }.sum
      unless sum != amount
        amounts.last[:amount] += (amount - sum)
      end
    end
    return amounts
  end

  # Returns the currency precision to use in affair
  def currency_precision(default = 2)
    FinancialYear.at.currency_precision || default
  end


end
