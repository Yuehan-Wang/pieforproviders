# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
# rubocop:disable RSpec/NestedGroups
RSpec.describe Nebraska::CalculatedServiceDay, type: :model do
  describe '#earned_revenue' do
    let!(:child) { create(:necc_child) }
    let(:attendance) { build(:attendance, child_approval: child.child_approvals.first) }
    let(:service_day) { attendance.service_day }
    let(:schedule) do
      child.schedules.select do |schedule|
        schedule.weekday == attendance.check_in.to_date.wday &&
          schedule.effective_on <= attendance.check_in.to_date &&
          (schedule.expires_on.nil? || schedule.expires_on > attendance.check_in.to_date)
      end.first
    end
    let!(:nebraska_accredited_hourly_rate) do
      create(:accredited_hourly_ldds_rate,
             license_type: child.business.license_type,
             max_age: attendance.child.age + 4.years,
             effective_on: attendance.check_in - 1.year,
             expires_on: attendance.check_in + 1.year,
             county: attendance.county)
    end
    let!(:nebraska_accredited_daily_rate) do
      create(:accredited_daily_ldds_rate,
             license_type: child.business.license_type,
             max_age: attendance.child.age + 4.years,
             effective_on: attendance.check_in - 1.year,
             expires_on: attendance.check_in + 1.year,
             county: attendance.county)
    end
    let!(:nebraska_unaccredited_hourly_rate) do
      create(:unaccredited_hourly_ldds_rate,
             license_type: child.business.license_type,
             max_age: attendance.child.age + 4.years,
             effective_on: attendance.check_in - 1.year,
             expires_on: attendance.check_in + 1.year,
             county: attendance.county)
    end
    let!(:nebraska_unaccredited_daily_rate) do
      create(:unaccredited_daily_ldds_rate,
             license_type: child.business.license_type,
             max_age: attendance.child.age + 4.years,
             effective_on: attendance.check_in - 1.year,
             expires_on: attendance.check_in + 1.year,
             county: attendance.county)
    end
    let!(:nebraska_school_age_unaccredited_hourly_rate) do
      create(:unaccredited_hourly_ldds_school_age_rate,
             license_type: child.business.license_type,
             effective_on: attendance.check_in - 1.year,
             expires_on: attendance.check_in + 1.year,
             county: attendance.county)
    end
    let!(:nebraska_school_age_unaccredited_daily_rate) do
      create(:unaccredited_daily_ldds_school_age_rate,
             license_type: child.business.license_type,
             effective_on: attendance.check_in - 1.year,
             expires_on: attendance.check_in + 1.year,
             county: attendance.county)
    end
    let!(:nebraska_school_age_unaccredited_non_urban_hourly_rate) do
      create(:unaccredited_hourly_other_region_school_age_rate,
             license_type: child.business.license_type,
             effective_on: attendance.check_in - 1.year,
             expires_on: attendance.check_in + 1.year,
             county: attendance.county)
    end
    let!(:nebraska_school_age_unaccredited_non_urban_daily_rate) do
      create(:unaccredited_daily_other_region_school_age_rate,
             license_type: child.business.license_type,
             effective_on: attendance.check_in - 1.year,
             expires_on: attendance.check_in + 1.year,
             county: attendance.county)
    end

    let(:rates) do
      NebraskaRate.for_case(
        service_day.date,
        attendance.child_approval&.enrolled_in_school || false,
        attendance.child.age_in_months(service_day.date),
        attendance.business
      )
    end

    before { attendance.business.update!(county: 'Douglas') }

    context 'with an accredited business' do
      before do
        attendance.business.update!(accredited: true, qris_rating: 'not_rated')
        attendance.child_approval.update!(special_needs_rate: false)
      end

      it 'gets rates for an hourly-only attendance' do
        attendance.check_out = attendance.check_in + 3.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(3.25 * nebraska_accredited_hourly_rate.amount)
      end

      it 'gets rates for a daily-only attendance' do
        attendance.check_out = attendance.check_in + 6.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(1 * nebraska_accredited_daily_rate.amount)
      end

      it 'gets rates for a daily-plus-hourly attendance' do
        attendance.check_out = attendance.check_in + 12.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(
          (2.25 * nebraska_accredited_hourly_rate.amount) + (1 * nebraska_accredited_daily_rate.amount)
        )
      end

      it 'gets rates for an attendance at the max of 18 hours' do
        attendance.check_out = attendance.check_in + 21.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(
          (8 * nebraska_accredited_hourly_rate.amount) + (1 * nebraska_accredited_daily_rate.amount)
        )
      end

      it 'gets rates for two attendances that keep the service day within an hourly duration' do
        attendance.check_out = attendance.check_in + 1.hour + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        create(
          :attendance,
          service_day: service_day,
          child_approval: attendance.child_approval,
          check_in: attendance.check_in + 2.hours + 0.minutes,
          check_out: attendance.check_in + 2.hours + 30.minutes
        )
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(1.75 * nebraska_accredited_hourly_rate.amount)
      end

      it 'gets rates for two attendances that make up a full day' do
        attendance.check_out = attendance.check_in + 1.hour + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        create(
          :attendance,
          child_approval: attendance.child_approval,
          check_in: attendance.check_in + 2.hours + 0.minutes,
          check_out: attendance.check_in + 8.hours + 30.minutes
        )
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(1 * nebraska_accredited_daily_rate.amount)
      end

      it 'gets rates for two attendances that make up a full day plus hourly' do
        attendance.check_out = attendance.check_in + 4.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        create(
          :attendance,
          child_approval: attendance.child_approval,
          check_in: attendance.check_in + 5.hours + 0.minutes,
          check_out: attendance.check_in + 12.hours + 30.minutes
        )
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(
          (1 * nebraska_accredited_daily_rate.amount) +
            (1.75 * nebraska_accredited_hourly_rate.amount)
        )
      end

      it 'gets rates for two attendances that exceed the max of 18 hours' do
        attendance.check_out = attendance.check_in + 3.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        create(
          :attendance,
          child_approval: attendance.child_approval,
          check_in: attendance.check_in + 5.hours + 0.minutes,
          check_out: attendance.check_in + 20.hours + 30.minutes
        )
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(
          (1 * nebraska_accredited_daily_rate.amount) +
            (8 * nebraska_accredited_hourly_rate.amount)
        )
      end

      context 'with a special needs approved child' do
        before do
          attendance.business.update!(accredited: true, qris_rating: 'not_rated')
          attendance.child_approval.update!(
            special_needs_rate: true,
            special_needs_daily_rate: 20.0,
            special_needs_hourly_rate: 5.60
          )
        end

        it 'gets rates for an hourly-only attendance' do
          attendance.check_out = attendance.check_in + 3.hours + 12.minutes
          attendance.save!
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(3.25 * attendance.child_approval.special_needs_hourly_rate)
        end

        it 'gets rates for a daily-only attendance' do
          attendance.check_out = attendance.check_in + 6.hours + 12.minutes
          attendance.save!
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(1 * attendance.child_approval.special_needs_daily_rate)
        end

        it 'gets rates for a daily-plus-hourly attendance' do
          attendance.check_out = attendance.check_in + 12.hours + 12.minutes
          attendance.save!
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(
            (2.25 * attendance.child_approval.special_needs_hourly_rate) +
            (1 * attendance.child_approval.special_needs_daily_rate)
          )
        end

        it 'gets rates for an attendance at the max of 18 hours' do
          attendance.check_out = attendance.check_in + 21.hours + 12.minutes
          attendance.save!
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(
            (8 * attendance.child_approval.special_needs_hourly_rate) +
            (1 * attendance.child_approval.special_needs_daily_rate)
          )
        end

        it 'gets rates for two attendances that keep the service day within an hourly duration' do
          attendance.check_out = attendance.check_in + 1.hour + 12.minutes
          attendance.save!
          perform_enqueued_jobs
          service_day.reload
          create(
            :attendance,
            service_day: service_day,
            child_approval: attendance.child_approval,
            check_in: attendance.check_in + 2.hours + 0.minutes,
            check_out: attendance.check_in + 2.hours + 30.minutes
          )
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(1.75 * attendance.child_approval.special_needs_hourly_rate)
        end

        it 'gets rates for two attendances that make up a full day' do
          attendance.check_out = attendance.check_in + 1.hour + 12.minutes
          attendance.save!
          perform_enqueued_jobs
          service_day.reload
          create(
            :attendance,
            child_approval: attendance.child_approval,
            check_in: attendance.check_in + 2.hours + 0.minutes,
            check_out: attendance.check_in + 8.hours + 30.minutes
          )
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(1 * attendance.child_approval.special_needs_daily_rate)
        end

        it 'gets rates for two attendances that make up a full day plus hourly' do
          attendance.check_out = attendance.check_in + 4.hours + 12.minutes
          attendance.save!
          create(
            :attendance,
            child_approval: attendance.child_approval,
            check_in: attendance.check_in + 5.hours + 0.minutes,
            check_out: attendance.check_in + 12.hours + 30.minutes
          )
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(
            (1 * attendance.child_approval.special_needs_daily_rate) +
              (1.75 * attendance.child_approval.special_needs_hourly_rate)
          )
        end

        it 'gets rates for two attendances that exceed the max of 18 hours' do
          attendance.check_out = attendance.check_in + 3.hours + 12.minutes
          attendance.save!
          create(
            :attendance,
            child_approval: attendance.child_approval,
            check_in: attendance.check_in + 5.hours + 0.minutes,
            check_out: attendance.check_in + 20.hours + 30.minutes
          )
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(
            (1 * attendance.child_approval.special_needs_daily_rate) +
              (8 * attendance.child_approval.special_needs_hourly_rate)
          )
        end
      end

      it 'changes rates when the attendance is edited' do
        attendance.check_out = attendance.check_in + 3.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(3.25 * nebraska_accredited_hourly_rate.amount)
        attendance.check_out = attendance.check_in + 6.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(1 * nebraska_accredited_daily_rate.amount)
      end
    end

    context 'with an unaccredited business' do
      before do
        attendance.business.update!(accredited: false, qris_rating: 'not_rated')
        attendance.child_approval.update!(special_needs_rate: false)
      end

      it 'gets rates for an hourly-only attendance' do
        attendance.check_out = attendance.check_in + 3.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(3.25 * nebraska_unaccredited_hourly_rate.amount)
      end

      it 'gets rates for a daily-only attendance' do
        attendance.check_out = attendance.check_in + 6.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(1 * nebraska_unaccredited_daily_rate.amount)
      end

      it 'gets rates for a daily-plus-hourly attendance' do
        attendance.check_out = attendance.check_in + 12.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(
          (2.25 * nebraska_unaccredited_hourly_rate.amount) +
          (1 * nebraska_unaccredited_daily_rate.amount)
        )
      end

      it 'gets rates for an attendance at the max of 18 hours' do
        attendance.check_out = attendance.check_in + 21.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(
          (8 * nebraska_unaccredited_hourly_rate.amount) +
          (1 * nebraska_unaccredited_daily_rate.amount)
        )
      end

      it 'gets rates for two attendances that keep the service day within an hourly duration' do
        attendance.check_out = attendance.check_in + 1.hour + 12.minutes
        attendance.save!
        create(
          :attendance,
          service_day: service_day,
          child_approval: attendance.child_approval,
          check_in: attendance.check_in + 2.hours + 0.minutes,
          check_out: attendance.check_in + 2.hours + 30.minutes
        )
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(1.75 * nebraska_unaccredited_hourly_rate.amount)
      end

      it 'gets rates for two attendances that make up a full day' do
        attendance.check_out = attendance.check_in + 1.hour + 12.minutes
        attendance.save!
        create(
          :attendance,
          child_approval: attendance.child_approval,
          check_in: attendance.check_in + 2.hours + 0.minutes,
          check_out: attendance.check_in + 8.hours + 30.minutes
        )
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(1 * nebraska_unaccredited_daily_rate.amount)
      end

      it 'gets rates for two attendances that make up a full day plus hourly' do
        attendance.check_out = attendance.check_in + 4.hours + 12.minutes
        attendance.save!
        create(
          :attendance,
          child_approval: attendance.child_approval,
          check_in: attendance.check_in + 5.hours + 0.minutes,
          check_out: attendance.check_in + 12.hours + 30.minutes
        )
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(
          (1 * nebraska_unaccredited_daily_rate.amount) +
            (1.75 * nebraska_unaccredited_hourly_rate.amount)
        )
      end

      it 'gets rates for two attendances that exceed the max of 18 hours' do
        attendance.check_out = attendance.check_in + 3.hours + 12.minutes
        attendance.save!
        create(
          :attendance,
          child_approval: attendance.child_approval,
          check_in: attendance.check_in + 5.hours + 0.minutes,
          check_out: attendance.check_in + 20.hours + 30.minutes
        )
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(
          (1 * nebraska_unaccredited_daily_rate.amount) +
            (8 * nebraska_unaccredited_hourly_rate.amount)
        )
      end

      context 'with a special needs approved child' do
        before do
          attendance.business.update!(accredited: true, qris_rating: 'not_rated')
          attendance.child_approval.update!(
            special_needs_rate: true,
            special_needs_daily_rate: 20.0,
            special_needs_hourly_rate: 5.60
          )
        end

        it 'gets rates for an hourly-only attendance' do
          attendance.check_out = attendance.check_in + 3.hours + 12.minutes
          attendance.save!
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(3.25 * attendance.child_approval.special_needs_hourly_rate)
        end

        it 'gets rates for a daily-only attendance' do
          attendance.check_out = attendance.check_in + 6.hours + 12.minutes
          attendance.save!
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(1 * attendance.child_approval.special_needs_daily_rate)
        end

        it 'gets rates for a daily-plus-hourly attendance' do
          attendance.check_out = attendance.check_in + 12.hours + 12.minutes
          attendance.save!
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(
            (2.25 * attendance.child_approval.special_needs_hourly_rate) +
            (1 * attendance.child_approval.special_needs_daily_rate)
          )
        end

        it 'gets rates for an attendance at the max of 18 hours' do
          attendance.check_out = attendance.check_in + 21.hours + 12.minutes
          attendance.save!
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(
            (8 * attendance.child_approval.special_needs_hourly_rate) +
            (1 * attendance.child_approval.special_needs_daily_rate)
          )
        end

        it 'gets rates for two attendances that keep the service day within an hourly duration' do
          attendance.check_out = attendance.check_in + 1.hour + 12.minutes
          attendance.save!
          create(
            :attendance,
            service_day: service_day,
            child_approval: attendance.child_approval,
            check_in: attendance.check_in + 2.hours + 0.minutes,
            check_out: attendance.check_in + 2.hours + 30.minutes
          )
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(1.75 * attendance.child_approval.special_needs_hourly_rate)
        end

        it 'gets rates for two attendances that make up a full day' do
          attendance.check_out = attendance.check_in + 1.hour + 12.minutes
          attendance.save!
          create(
            :attendance,
            child_approval: attendance.child_approval,
            check_in: attendance.check_in + 2.hours + 0.minutes,
            check_out: attendance.check_in + 8.hours + 30.minutes
          )
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(1 * attendance.child_approval.special_needs_daily_rate)
        end

        it 'gets rates for two attendances that make up a full day plus hourly' do
          attendance.check_out = attendance.check_in + 4.hours + 12.minutes
          attendance.save!
          create(
            :attendance,
            child_approval: attendance.child_approval,
            check_in: attendance.check_in + 5.hours + 0.minutes,
            check_out: attendance.check_in + 12.hours + 30.minutes
          )
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(
            (1 * attendance.child_approval.special_needs_daily_rate) +
              (1.75 * attendance.child_approval.special_needs_hourly_rate)
          )
        end

        it 'gets rates for two attendances that exceed the max of 18 hours' do
          attendance.check_out = attendance.check_in + 3.hours + 12.minutes
          attendance.save!
          create(
            :attendance,
            child_approval: attendance.child_approval,
            check_in: attendance.check_in + 5.hours + 0.minutes,
            check_out: attendance.check_in + 20.hours + 30.minutes
          )
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(
            (1 * attendance.child_approval.special_needs_daily_rate) +
              (8 * attendance.child_approval.special_needs_hourly_rate)
          )
        end
      end

      it 'changes rates when the attendance is edited' do
        attendance.check_out = attendance.check_in + 3.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(3.25 * nebraska_unaccredited_hourly_rate.amount)
        attendance.check_out = attendance.check_in + 6.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(1 * nebraska_unaccredited_daily_rate.amount)
      end
    end

    context 'with an accredited business with a qris_bump' do
      before do
        attendance.business.update!(accredited: true, qris_rating: 'step_five')
        attendance.child_approval.update!(special_needs_rate: false)
      end

      it 'gets rates for an hourly-only attendance' do
        attendance.check_out = attendance.check_in + 3.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(3.25 * nebraska_accredited_hourly_rate.amount * (1.05**2))
      end

      it 'gets rates for a daily-only attendance' do
        attendance.check_out = attendance.check_in + 6.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(1 * nebraska_accredited_daily_rate.amount * (1.05**2))
      end

      it 'gets rates for a daily-plus-hourly attendance' do
        attendance.check_out = attendance.check_in + 12.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(
          (2.25 * nebraska_accredited_hourly_rate.amount * (1.05**2)) +
          (1 * nebraska_accredited_daily_rate.amount * (1.05**2))
        )
      end

      it 'gets rates for an attendance at the max of 18 hours' do
        attendance.check_out = attendance.check_in + 21.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(
          (8 * nebraska_accredited_hourly_rate.amount * (1.05**2)) +
          (1 * nebraska_accredited_daily_rate.amount * (1.05**2))
        )
      end

      it 'gets rates for two attendances that keep the service day within an hourly duration' do
        attendance.check_out = attendance.check_in + 1.hour + 12.minutes
        attendance.save!
        create(
          :attendance,
          service_day: service_day,
          child_approval: attendance.child_approval,
          check_in: attendance.check_in + 2.hours + 0.minutes,
          check_out: attendance.check_in + 2.hours + 30.minutes
        )
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(1.75 * nebraska_accredited_hourly_rate.amount * (1.05**2))
      end

      it 'gets rates for two attendances that make up a full day' do
        attendance.check_out = attendance.check_in + 1.hour + 12.minutes
        attendance.save!
        create(
          :attendance,
          child_approval: attendance.child_approval,
          check_in: attendance.check_in + 2.hours + 0.minutes,
          check_out: attendance.check_in + 8.hours + 30.minutes
        )
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(1 * nebraska_accredited_daily_rate.amount * (1.05**2))
      end

      it 'gets rates for two attendances that make up a full day plus hourly' do
        attendance.check_out = attendance.check_in + 4.hours + 12.minutes
        attendance.save!
        create(
          :attendance,
          child_approval: attendance.child_approval,
          check_in: attendance.check_in + 5.hours + 0.minutes,
          check_out: attendance.check_in + 12.hours + 30.minutes
        )
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(
          (1 * nebraska_accredited_daily_rate.amount * (1.05**2)) +
            (1.75 * nebraska_accredited_hourly_rate.amount * (1.05**2))
        )
      end

      it 'gets rates for two attendances that exceed the max of 18 hours' do
        attendance.check_out = attendance.check_in + 3.hours + 12.minutes
        attendance.save!
        create(
          :attendance,
          child_approval: attendance.child_approval,
          check_in: attendance.check_in + 5.hours + 0.minutes,
          check_out: attendance.check_in + 20.hours + 30.minutes
        )
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(
          (1 * nebraska_accredited_daily_rate.amount * (1.05**2)) +
            (8 * nebraska_accredited_hourly_rate.amount * (1.05**2))
        )
      end

      context 'with a special needs approved child' do
        before do
          attendance.business.update!(accredited: true, qris_rating: 'step_five')
          attendance.child_approval.update!(
            special_needs_rate: true,
            special_needs_daily_rate: 20.0,
            special_needs_hourly_rate: 5.60
          )
        end

        it 'gets rates for an hourly-only attendance' do
          attendance.check_out = attendance.check_in + 3.hours + 12.minutes
          attendance.save!
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(3.25 * attendance.child_approval.special_needs_hourly_rate)
        end

        it 'gets rates for a daily-only attendance' do
          attendance.check_out = attendance.check_in + 6.hours + 12.minutes
          attendance.save!
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(1 * attendance.child_approval.special_needs_daily_rate)
        end

        it 'gets rates for a daily-plus-hourly attendance' do
          attendance.check_out = attendance.check_in + 12.hours + 12.minutes
          attendance.save!
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(
            (2.25 * attendance.child_approval.special_needs_hourly_rate) +
            (1 * attendance.child_approval.special_needs_daily_rate)
          )
        end

        it 'gets rates for an attendance at the max of 18 hours' do
          attendance.check_out = attendance.check_in + 21.hours + 12.minutes
          attendance.save!
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(
            (8 * attendance.child_approval.special_needs_hourly_rate) +
            (1 * attendance.child_approval.special_needs_daily_rate)
          )
        end

        it 'gets rates for two attendances that keep the service day within an hourly duration' do
          attendance.check_out = attendance.check_in + 1.hour + 12.minutes
          attendance.save!
          create(
            :attendance,
            service_day: service_day,
            child_approval: attendance.child_approval,
            check_in: attendance.check_in + 2.hours + 0.minutes,
            check_out: attendance.check_in + 2.hours + 30.minutes
          )
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(1.75 * attendance.child_approval.special_needs_hourly_rate)
        end

        it 'gets rates for two attendances that make up a full day' do
          attendance.check_out = attendance.check_in + 1.hour + 12.minutes
          attendance.save!
          create(
            :attendance,
            child_approval: attendance.child_approval,
            check_in: attendance.check_in + 2.hours + 0.minutes,
            check_out: attendance.check_in + 8.hours + 30.minutes
          )
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(1 * attendance.child_approval.special_needs_daily_rate)
        end

        it 'gets rates for two attendances that make up a full day plus hourly' do
          attendance.check_out = attendance.check_in + 4.hours + 12.minutes
          attendance.save!
          create(
            :attendance,
            child_approval: attendance.child_approval,
            check_in: attendance.check_in + 5.hours + 0.minutes,
            check_out: attendance.check_in + 12.hours + 30.minutes
          )
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(
            (1 * attendance.child_approval.special_needs_daily_rate) +
              (1.75 * attendance.child_approval.special_needs_hourly_rate)
          )
        end

        it 'gets rates for two attendances that exceed the max of 18 hours' do
          attendance.check_out = attendance.check_in + 3.hours + 12.minutes
          attendance.save!
          create(
            :attendance,
            child_approval: attendance.child_approval,
            check_in: attendance.check_in + 5.hours + 0.minutes,
            check_out: attendance.check_in + 20.hours + 30.minutes
          )
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(
            (1 * attendance.child_approval.special_needs_daily_rate) +
              (8 * attendance.child_approval.special_needs_hourly_rate)
          )
        end
      end

      it 'changes rates when the attendance is edited' do
        attendance.check_out = attendance.check_in + 3.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(3.25 * nebraska_accredited_hourly_rate.amount * (1.05**2))
        attendance.check_out = attendance.check_in + 6.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(1 * nebraska_accredited_daily_rate.amount * (1.05**2))
      end
    end

    context 'with an unaccredited business with a qris_bump' do
      before do
        attendance.business.update!(accredited: false, qris_rating: 'step_five')
        attendance.child_approval.update!(special_needs_rate: false)
      end

      it 'gets rates for an hourly-only attendance' do
        attendance.check_out = attendance.check_in + 3.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(3.25 * nebraska_unaccredited_hourly_rate.amount * (1.05**3))
      end

      it 'gets rates for a daily-only attendance' do
        attendance.check_out = attendance.check_in + 6.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(1 * nebraska_unaccredited_daily_rate.amount * (1.05**3))
      end

      it 'gets rates for a daily-plus-hourly attendance' do
        attendance.check_out = attendance.check_in + 12.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(
          (2.25 * nebraska_unaccredited_hourly_rate.amount * (1.05**3)) +
          (1 * nebraska_unaccredited_daily_rate.amount * (1.05**3))
        )
      end

      it 'gets rates for an attendance at the max of 18 hours' do
        attendance.check_out = attendance.check_in + 21.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(
          (8 * nebraska_unaccredited_hourly_rate.amount * (1.05**3)) +
          (1 * nebraska_unaccredited_daily_rate.amount * (1.05**3))
        )
      end

      it 'gets rates for two attendances that keep the service day within an hourly duration' do
        attendance.check_out = attendance.check_in + 1.hour + 12.minutes
        attendance.save!
        create(
          :attendance,
          service_day: service_day,
          child_approval: attendance.child_approval,
          check_in: attendance.check_in + 2.hours + 0.minutes,
          check_out: attendance.check_in + 2.hours + 30.minutes
        )
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(1.75 * nebraska_unaccredited_hourly_rate.amount * (1.05**3))
      end

      it 'gets rates for two attendances that make up a full day' do
        attendance.check_out = attendance.check_in + 1.hour + 12.minutes
        attendance.save!
        create(
          :attendance,
          child_approval: attendance.child_approval,
          check_in: attendance.check_in + 2.hours + 0.minutes,
          check_out: attendance.check_in + 8.hours + 30.minutes
        )
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(1 * nebraska_unaccredited_daily_rate.amount * (1.05**3))
      end

      it 'gets rates for two attendances that make up a full day plus hourly' do
        attendance.check_out = attendance.check_in + 4.hours + 12.minutes
        attendance.save!
        create(
          :attendance,
          child_approval: attendance.child_approval,
          check_in: attendance.check_in + 5.hours + 0.minutes,
          check_out: attendance.check_in + 12.hours + 30.minutes
        )
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(
          (1 * nebraska_unaccredited_daily_rate.amount * (1.05**3)) +
            (1.75 * nebraska_unaccredited_hourly_rate.amount * (1.05**3))
        )
      end

      it 'gets rates for two attendances that exceed the max of 18 hours' do
        attendance.check_out = attendance.check_in + 3.hours + 12.minutes
        attendance.save!
        create(
          :attendance,
          child_approval: attendance.child_approval,
          check_in: attendance.check_in + 5.hours + 0.minutes,
          check_out: attendance.check_in + 20.hours + 30.minutes
        )
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(
          (1 * nebraska_unaccredited_daily_rate.amount * (1.05**3)) +
            (8 * nebraska_unaccredited_hourly_rate.amount * (1.05**3))
        )
      end

      context 'with a special needs approved child' do
        before do
          attendance.business.update!(accredited: true, qris_rating: 'step_five')
          attendance.child_approval.update!(
            special_needs_rate: true,
            special_needs_daily_rate: 20.0,
            special_needs_hourly_rate: 5.60
          )
        end

        it 'gets rates for an hourly-only attendance' do
          attendance.check_out = attendance.check_in + 3.hours + 12.minutes
          attendance.save!
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(3.25 * attendance.child_approval.special_needs_hourly_rate)
        end

        it 'gets rates for a daily-only attendance' do
          attendance.check_out = attendance.check_in + 6.hours + 12.minutes
          attendance.save!
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(1 * attendance.child_approval.special_needs_daily_rate)
        end

        it 'gets rates for a daily-plus-hourly attendance' do
          attendance.check_out = attendance.check_in + 12.hours + 12.minutes
          attendance.save!
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(
            (2.25 * attendance.child_approval.special_needs_hourly_rate) +
            (1 * attendance.child_approval.special_needs_daily_rate)
          )
        end

        it 'gets rates for an attendance at the max of 18 hours' do
          attendance.check_out = attendance.check_in + 21.hours + 12.minutes
          attendance.save!
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(
            (8 * attendance.child_approval.special_needs_hourly_rate) +
            (1 * attendance.child_approval.special_needs_daily_rate)
          )
        end

        it 'gets rates for two attendances that keep the service day within an hourly duration' do
          attendance.check_out = attendance.check_in + 1.hour + 12.minutes
          attendance.save!
          create(
            :attendance,
            service_day: service_day,
            child_approval: attendance.child_approval,
            check_in: attendance.check_in + 2.hours + 0.minutes,
            check_out: attendance.check_in + 2.hours + 30.minutes
          )
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(1.75 * attendance.child_approval.special_needs_hourly_rate)
        end

        it 'gets rates for two attendances that make up a full day' do
          attendance.check_out = attendance.check_in + 1.hour + 12.minutes
          attendance.save!
          create(
            :attendance,
            child_approval: attendance.child_approval,
            check_in: attendance.check_in + 2.hours + 0.minutes,
            check_out: attendance.check_in + 8.hours + 30.minutes
          )
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(1 * attendance.child_approval.special_needs_daily_rate)
        end

        it 'gets rates for two attendances that make up a full day plus hourly' do
          attendance.check_out = attendance.check_in + 4.hours + 12.minutes
          attendance.save!
          create(
            :attendance,
            child_approval: attendance.child_approval,
            check_in: attendance.check_in + 5.hours + 0.minutes,
            check_out: attendance.check_in + 12.hours + 30.minutes
          )
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(
            (1 * attendance.child_approval.special_needs_daily_rate) +
              (1.75 * attendance.child_approval.special_needs_hourly_rate)
          )
        end

        it 'gets rates for two attendances that exceed the max of 18 hours' do
          attendance.check_out = attendance.check_in + 3.hours + 12.minutes
          attendance.save!
          create(
            :attendance,
            child_approval: attendance.child_approval,
            check_in: attendance.check_in + 5.hours + 0.minutes,
            check_out: attendance.check_in + 20.hours + 30.minutes
          )
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(
            (1 * attendance.child_approval.special_needs_daily_rate) +
              (8 * attendance.child_approval.special_needs_hourly_rate)
          )
        end
      end

      it 'changes rates when the attendance is edited' do
        attendance.check_out = attendance.check_in + 3.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(3.25 * nebraska_unaccredited_hourly_rate.amount * (1.05**3))
        attendance.check_out = attendance.check_in + 6.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(1 * nebraska_unaccredited_daily_rate.amount * (1.05**3))
      end
    end

    context 'with a school age child with an unaccredited qris bump' do
      before do
        attendance.business.update!(accredited: false, qris_rating: 'step_five')
        attendance.child_approval.update!(special_needs_rate: false, enrolled_in_school: true)
      end

      it 'gets rates for an hourly-only attendance' do
        attendance.check_out = attendance.check_in + 3.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(3.25 * nebraska_school_age_unaccredited_hourly_rate.amount * (1.05**3))
      end

      it 'gets rates for a daily-only attendance' do
        attendance.check_out = attendance.check_in + 6.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(1 * nebraska_school_age_unaccredited_daily_rate.amount * (1.05**3))
      end

      it 'gets rates for a daily-plus-hourly attendance' do
        attendance.check_out = attendance.check_in + 12.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(
          (2.25 * nebraska_school_age_unaccredited_hourly_rate.amount * (1.05**3)) +
          (1 * nebraska_school_age_unaccredited_daily_rate.amount * (1.05**3))
        )
      end

      it 'gets rates for an attendance at the max of 18 hours' do
        attendance.check_out = attendance.check_in + 21.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(
          (8 * nebraska_school_age_unaccredited_hourly_rate.amount * (1.05**3)) +
          (1 * nebraska_school_age_unaccredited_daily_rate.amount * (1.05**3))
        )
      end

      it 'gets rates for two attendances that keep the service day within an hourly duration' do
        attendance.check_out = attendance.check_in + 1.hour + 12.minutes
        attendance.save!
        create(
          :attendance,
          service_day: service_day,
          child_approval: attendance.child_approval,
          check_in: attendance.check_in + 2.hours + 0.minutes,
          check_out: attendance.check_in + 2.hours + 30.minutes
        )
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(1.75 * nebraska_school_age_unaccredited_hourly_rate.amount * (1.05**3))
      end

      it 'gets rates for two attendances that make up a full day' do
        attendance.check_out = attendance.check_in + 1.hour + 12.minutes
        attendance.save!
        create(
          :attendance,
          child_approval: attendance.child_approval,
          check_in: attendance.check_in + 2.hours + 0.minutes,
          check_out: attendance.check_in + 8.hours + 30.minutes
        )
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(1 * nebraska_school_age_unaccredited_daily_rate.amount * (1.05**3))
      end

      it 'gets rates for two attendances that make up a full day plus hourly' do
        attendance.check_out = attendance.check_in + 4.hours + 12.minutes
        attendance.save!
        create(
          :attendance,
          child_approval: attendance.child_approval,
          check_in: attendance.check_in + 5.hours + 0.minutes,
          check_out: attendance.check_in + 12.hours + 30.minutes
        )
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(
          (1 * nebraska_school_age_unaccredited_daily_rate.amount * (1.05**3)) +
            (1.75 * nebraska_school_age_unaccredited_hourly_rate.amount * (1.05**3))
        )
      end

      it 'gets rates for two attendances that exceed the max of 18 hours' do
        attendance.check_out = attendance.check_in + 3.hours + 12.minutes
        attendance.save!
        create(
          :attendance,
          child_approval: attendance.child_approval,
          check_in: attendance.check_in + 5.hours + 0.minutes,
          check_out: attendance.check_in + 20.hours + 30.minutes
        )
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(
          (1 * nebraska_school_age_unaccredited_daily_rate.amount * (1.05**3)) +
            (8 * nebraska_school_age_unaccredited_hourly_rate.amount * (1.05**3))
        )
      end

      context 'with a special needs approved child' do
        before do
          attendance.business.update!(accredited: true, qris_rating: 'step_five')
          attendance.child_approval.update!(
            special_needs_rate: true,
            special_needs_daily_rate: 20.0,
            special_needs_hourly_rate: 5.60
          )
        end

        it 'gets rates for an hourly-only attendance' do
          attendance.check_out = attendance.check_in + 3.hours + 12.minutes
          attendance.save!
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(3.25 * attendance.child_approval.special_needs_hourly_rate)
        end

        it 'gets rates for a daily-only attendance' do
          attendance.check_out = attendance.check_in + 6.hours + 12.minutes
          attendance.save!
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(1 * attendance.child_approval.special_needs_daily_rate)
        end

        it 'gets rates for a daily-plus-hourly attendance' do
          attendance.check_out = attendance.check_in + 12.hours + 12.minutes
          attendance.save!
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(
            (2.25 * attendance.child_approval.special_needs_hourly_rate) +
            (1 * attendance.child_approval.special_needs_daily_rate)
          )
        end

        it 'gets rates for an attendance at the max of 18 hours' do
          attendance.check_out = attendance.check_in + 21.hours + 12.minutes
          attendance.save!
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(
            (8 * attendance.child_approval.special_needs_hourly_rate) +
            (1 * attendance.child_approval.special_needs_daily_rate)
          )
        end

        it 'gets rates for two attendances that keep the service day within an hourly duration' do
          attendance.check_out = attendance.check_in + 1.hour + 12.minutes
          attendance.save!
          create(
            :attendance,
            service_day: service_day,
            child_approval: attendance.child_approval,
            check_in: attendance.check_in + 2.hours + 0.minutes,
            check_out: attendance.check_in + 2.hours + 30.minutes
          )
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(1.75 * attendance.child_approval.special_needs_hourly_rate)
        end

        it 'gets rates for two attendances that make up a full day' do
          attendance.check_out = attendance.check_in + 1.hour + 12.minutes
          attendance.save!
          create(
            :attendance,
            child_approval: attendance.child_approval,
            check_in: attendance.check_in + 2.hours + 0.minutes,
            check_out: attendance.check_in + 8.hours + 30.minutes
          )
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(1 * attendance.child_approval.special_needs_daily_rate)
        end

        it 'gets rates for two attendances that make up a full day plus hourly' do
          attendance.check_out = attendance.check_in + 4.hours + 12.minutes
          attendance.save!
          create(
            :attendance,
            child_approval: attendance.child_approval,
            check_in: attendance.check_in + 5.hours + 0.minutes,
            check_out: attendance.check_in + 12.hours + 30.minutes
          )
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(
            (1 * attendance.child_approval.special_needs_daily_rate) +
              (1.75 * attendance.child_approval.special_needs_hourly_rate)
          )
        end

        it 'gets rates for two attendances that exceed the max of 18 hours' do
          attendance.check_out = attendance.check_in + 3.hours + 12.minutes
          attendance.save!
          create(
            :attendance,
            child_approval: attendance.child_approval,
            check_in: attendance.check_in + 5.hours + 0.minutes,
            check_out: attendance.check_in + 20.hours + 30.minutes
          )
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(
            (1 * attendance.child_approval.special_needs_daily_rate) +
              (8 * attendance.child_approval.special_needs_hourly_rate)
          )
        end
      end

      it 'changes rates when the attendance is edited' do
        attendance.check_out = attendance.check_in + 3.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(3.25 * nebraska_school_age_unaccredited_hourly_rate.amount * (1.05**3))
        attendance.check_out = attendance.check_in + 6.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(1 * nebraska_school_age_unaccredited_daily_rate.amount * (1.05**3))
      end
    end

    context 'with a school age child with an unaccredited qris bump in a non-LDDS county' do
      before do
        attendance.business.update!(accredited: false, qris_rating: 'step_five', county: 'Parker')
        attendance.child_approval.update!(special_needs_rate: false, enrolled_in_school: true)
      end

      it 'gets rates for an hourly-only attendance' do
        attendance.check_out = attendance.check_in + 3.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(3.25 * nebraska_school_age_unaccredited_non_urban_hourly_rate.amount * (1.05**3))
      end

      it 'gets rates for a daily-only attendance' do
        attendance.check_out = attendance.check_in + 6.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(1 * nebraska_school_age_unaccredited_non_urban_daily_rate.amount * (1.05**3))
      end

      it 'gets rates for a daily-plus-hourly attendance' do
        attendance.check_out = attendance.check_in + 12.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(
          (2.25 * nebraska_school_age_unaccredited_non_urban_hourly_rate.amount * (1.05**3)) +
          (1 * nebraska_school_age_unaccredited_non_urban_daily_rate.amount * (1.05**3))
        )
      end

      it 'gets rates for an attendance at the max of 18 hours' do
        attendance.check_out = attendance.check_in + 21.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(
          (8 * nebraska_school_age_unaccredited_non_urban_hourly_rate.amount * (1.05**3)) +
          (1 * nebraska_school_age_unaccredited_non_urban_daily_rate.amount * (1.05**3))
        )
      end

      it 'gets rates for two attendances that keep the service day within an hourly duration' do
        attendance.check_out = attendance.check_in + 1.hour + 12.minutes
        attendance.save!
        create(
          :attendance,
          service_day: service_day,
          child_approval: attendance.child_approval,
          check_in: attendance.check_in + 2.hours + 0.minutes,
          check_out: attendance.check_in + 2.hours + 30.minutes
        )
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(1.75 * nebraska_school_age_unaccredited_non_urban_hourly_rate.amount * (1.05**3))
      end

      it 'gets rates for two attendances that make up a full day' do
        attendance.check_out = attendance.check_in + 1.hour + 12.minutes
        attendance.save!
        create(
          :attendance,
          child_approval: attendance.child_approval,
          check_in: attendance.check_in + 2.hours + 0.minutes,
          check_out: attendance.check_in + 8.hours + 30.minutes
        )
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(1 * nebraska_school_age_unaccredited_non_urban_daily_rate.amount * (1.05**3))
      end

      it 'gets rates for two attendances that make up a full day plus hourly' do
        attendance.check_out = attendance.check_in + 4.hours + 12.minutes
        attendance.save!
        create(
          :attendance,
          child_approval: attendance.child_approval,
          check_in: attendance.check_in + 5.hours + 0.minutes,
          check_out: attendance.check_in + 12.hours + 30.minutes
        )
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(
          (1 * nebraska_school_age_unaccredited_non_urban_daily_rate.amount * (1.05**3)) +
            (1.75 * nebraska_school_age_unaccredited_non_urban_hourly_rate.amount * (1.05**3))
        )
      end

      it 'gets rates for two attendances that exceed the max of 18 hours' do
        attendance.check_out = attendance.check_in + 3.hours + 12.minutes
        attendance.save!
        create(
          :attendance,
          child_approval: attendance.child_approval,
          check_in: attendance.check_in + 5.hours + 0.minutes,
          check_out: attendance.check_in + 20.hours + 30.minutes
        )
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(
          (1 * nebraska_school_age_unaccredited_non_urban_daily_rate.amount * (1.05**3)) +
            (8 * nebraska_school_age_unaccredited_non_urban_hourly_rate.amount * (1.05**3))
        )
      end

      context 'with a special needs approved child' do
        before do
          attendance.business.update!(accredited: true, qris_rating: 'step_five')
          attendance.child_approval.update!(
            special_needs_rate: true,
            special_needs_daily_rate: 20.0,
            special_needs_hourly_rate: 5.60
          )
        end

        it 'gets rates for an hourly-only attendance' do
          attendance.check_out = attendance.check_in + 3.hours + 12.minutes
          attendance.save!
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(3.25 * attendance.child_approval.special_needs_hourly_rate)
        end

        it 'gets rates for a daily-only attendance' do
          attendance.check_out = attendance.check_in + 6.hours + 12.minutes
          attendance.save!
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(1 * attendance.child_approval.special_needs_daily_rate)
        end

        it 'gets rates for a daily-plus-hourly attendance' do
          attendance.check_out = attendance.check_in + 12.hours + 12.minutes
          attendance.save!
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(
            (2.25 * attendance.child_approval.special_needs_hourly_rate) +
            (1 * attendance.child_approval.special_needs_daily_rate)
          )
        end

        it 'gets rates for an attendance at the max of 18 hours' do
          attendance.check_out = attendance.check_in + 21.hours + 12.minutes
          attendance.save!
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(
            (8 * attendance.child_approval.special_needs_hourly_rate) +
            (1 * attendance.child_approval.special_needs_daily_rate)
          )
        end

        it 'gets rates for two attendances that keep the service day within an hourly duration' do
          attendance.check_out = attendance.check_in + 1.hour + 12.minutes
          attendance.save!
          create(
            :attendance,
            service_day: service_day,
            child_approval: attendance.child_approval,
            check_in: attendance.check_in + 2.hours + 0.minutes,
            check_out: attendance.check_in + 2.hours + 30.minutes
          )
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(1.75 * attendance.child_approval.special_needs_hourly_rate)
        end

        it 'gets rates for two attendances that make up a full day' do
          attendance.check_out = attendance.check_in + 1.hour + 12.minutes
          attendance.save!
          create(
            :attendance,
            child_approval: attendance.child_approval,
            check_in: attendance.check_in + 2.hours + 0.minutes,
            check_out: attendance.check_in + 8.hours + 30.minutes
          )
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(1 * attendance.child_approval.special_needs_daily_rate)
        end

        it 'gets rates for two attendances that make up a full day plus hourly' do
          attendance.check_out = attendance.check_in + 4.hours + 12.minutes
          attendance.save!
          create(
            :attendance,
            child_approval: attendance.child_approval,
            check_in: attendance.check_in + 5.hours + 0.minutes,
            check_out: attendance.check_in + 12.hours + 30.minutes
          )
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(
            (1 * attendance.child_approval.special_needs_daily_rate) +
              (1.75 * attendance.child_approval.special_needs_hourly_rate)
          )
        end

        it 'gets rates for two attendances that exceed the max of 18 hours' do
          attendance.check_out = attendance.check_in + 3.hours + 12.minutes
          attendance.save!
          create(
            :attendance,
            child_approval: attendance.child_approval,
            check_in: attendance.check_in + 5.hours + 0.minutes,
            check_out: attendance.check_in + 20.hours + 30.minutes
          )
          perform_enqueued_jobs
          service_day.reload
          expect(
            described_class.new(
              service_day: attendance.service_day,
              child_approvals: attendance.child.child_approvals,
              rates: rates
            ).earned_revenue
          ).to eq(
            (1 * attendance.child_approval.special_needs_daily_rate) +
              (8 * attendance.child_approval.special_needs_hourly_rate)
          )
        end
      end

      it 'changes rates when the attendance is edited' do
        attendance.check_out = attendance.check_in + 3.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(3.25 * nebraska_school_age_unaccredited_non_urban_hourly_rate.amount * (1.05**3))
        attendance.check_out = attendance.check_in + 6.hours + 12.minutes
        attendance.save!
        perform_enqueued_jobs
        attendance.service_day.reload
        expect(
          described_class.new(
            service_day: attendance.service_day,
            child_approvals: attendance.child.child_approvals,
            rates: rates
          ).earned_revenue
        ).to eq(1 * nebraska_school_age_unaccredited_non_urban_daily_rate.amount * (1.05**3))
      end
    end
  end
end
# rubocop:enable RSpec/NestedGroups
# rubocop:enable Metrics/BlockLength
