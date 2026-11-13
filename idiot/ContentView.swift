//
//  ContentView.swift
//  idiot
//
//  Created by Umang on 26/7/26.
//

import SwiftData
import SwiftUI

#if os(iOS)
    struct PrivacyShield: View {
        var body: some View {
            Rectangle()
                .fill(Color.black)
                .ignoresSafeArea()
                .overlay {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
        }
    }
#endif

struct ContentView: View {
    @State private var selectedMonth = Date.now.startOfMonth
    @State private var showSettings = false
    @State private var showAnalytics = false
    #if os(iOS)
        @Environment(\.scenePhase) private var scenePhase
        @State private var isUnlocked = true
        @AppStorage("hideAmounts") private var hideAmounts = false
    #endif

    @AppStorage("filterHiddenCategoryIDs") private var hiddenCategoryIDsData: String = ""
    @AppStorage("filterMinAmount") private var minAmountText = ""
    @AppStorage("filterMaxAmount") private var maxAmountText = ""
    @AppStorage("filterShowIncome") private var showIncome = true
    @AppStorage("filterShowExpense") private var showExpense = true
    @AppStorage("filterShowInvestment") private var showInvestment = true
    @State private var hiddenCategoryIDs: Set<Category.ID> = []
    @State private var isFilterStateLoaded = false
    @State private var showAddTransaction = false
    @State private var editingTransaction: Transaction?

    private var newTransactionDate: Date {
        Calendar.current.isDate(selectedMonth, equalTo: .now, toGranularity: .month) ? .now : selectedMonth
    }

    private var hiddenCategoryIDsBinding: Binding<Set<Category.ID>> {
        Binding {
            hiddenCategoryIDs
        } set: { newValue in
            hiddenCategoryIDs = newValue
            if isFilterStateLoaded {
                hiddenCategoryIDsData = newValue.map(\.uuidString).sorted().joined(separator: ",")
            }
        }
    }

    private func loadPersistedFilters() {
        let ids = hiddenCategoryIDsData
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) }
        hiddenCategoryIDs = Set(ids)
        isFilterStateLoaded = true
    }

    private var minAmount: Double? {
        let trimmed = minAmountText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    private var maxAmount: Double? {
        let trimmed = maxAmountText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    #if os(iOS)
        private var walkableMonths: [Date] {
            let calendar = Calendar.current
            let current = Date.now.startOfMonth
            let past = (0 ..< 36).compactMap { calendar.date(byAdding: .month, value: -$0, to: current) }
            let future = (1 ... 3).compactMap { calendar.date(byAdding: .month, value: $0, to: current) }
            return past.reversed() + future
        }
    #endif

    var body: some View {
        platformHome
            .onAppear {
                loadPersistedFilters()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showAnalytics) {
                AnalyticsView()
            }
            .sheet(isPresented: $showAddTransaction) {
                TransactionFormView(transaction: nil, defaultDate: newTransactionDate)
            }
            .sheet(item: $editingTransaction) { transaction in
                TransactionFormView(transaction: transaction)
            }
            .onOpenURL { url in
                switch url.host {
                case "add":
                    showAddTransaction = true
                case "analytics":
                    #if os(macOS)
                        openAnalyticsWindow()
                    #else
                        showAnalytics = true
                    #endif
                default:
                    break
                }
            }
    }

    private var platformHome: some View {
        #if os(macOS)
            macHome
        #else
            iosHome
        #endif
    }

    #if os(macOS)
        var macHome: some View {
            HSplitView {
                WeeklyChartView(
                    selectedMonth: selectedMonth,
                    hiddenCategoryIDs: hiddenCategoryIDs,
                    minAmount: minAmount,
                    maxAmount: maxAmount,
                    showIncome: showIncome,
                    showExpense: showExpense,
                    showInvestment: showInvestment
                )
                .frame(minWidth: 480, idealWidth: 700, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                TransactionListView(
                    selectedMonth: selectedMonth,
                    showAddTransaction: $showAddTransaction,
                    editingTransaction: $editingTransaction,
                    hiddenCategoryIDs: hiddenCategoryIDsBinding,
                    minAmountText: $minAmountText,
                    maxAmountText: $maxAmountText,
                    showIncome: $showIncome,
                    showExpense: $showExpense,
                    showInvestment: $showInvestment
                )
                .frame(minWidth: 380, idealWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
            .toolbar {
                MonthlyHeaderView(
                    selectedMonth: $selectedMonth,
                    showAddTransaction: $showAddTransaction,
                    showSettings: $showSettings,
                    showHelp: $showHelp
                )
            }
            .sheet(isPresented: $showHelp) {
                NavigationStack {
                    HelpView()
                }
            }
        }
    #endif

    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
        @State private var showHelp = false

        private func openAnalyticsWindow() {
            openWindow(id: "analytics")
        }
    #endif

    #if os(iOS)
        var iosHome: some View {
            NavigationStack {
                TabView(selection: $selectedMonth) {
                    ForEach(walkableMonths, id: \.self) { month in
                        MonthPageView(
                            month: month,
                            showAddTransaction: $showAddTransaction,
                            editingTransaction: $editingTransaction,
                            hiddenCategoryIDs: hiddenCategoryIDsBinding,
                            minAmountText: $minAmountText,
                            maxAmountText: $maxAmountText,
                            showIncome: $showIncome,
                            showExpense: $showExpense,
                            showInvestment: $showInvestment
                        )
                        .tag(month)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .environment(\.amountsHidden, hideAmounts)
                .sheet(isPresented: $showHelpSheet) {
                    NavigationStack {
                        HelpView()
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") {
                                        showHelpSheet = false
                                    }
                                }
                            }
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        monthPickerButton
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                hideAmounts.toggle()
                            }
                        } label: {
                            Image(systemName: hideAmounts ? "eye.slash" : "eye")
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .accessibilityLabel(hideAmounts ? "Show amounts" : "Hide amounts")

                        Button {
                            showAnalytics = true
                        } label: {
                            Image(systemName: "chart.bar.xaxis")
                        }
                        .accessibilityLabel("Analytics")

                        Menu {
                            Button {
                                showHelpFromToolbar()
                            } label: {
                                Label("Help", systemImage: "questionmark.circle")
                            }

                            Button {
                                showSettings = true
                            } label: {
                                Label("Settings", systemImage: "gearshape")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("More options")
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
            }
            .ignoresSafeArea(.keyboard)
            .privacySensitive()
            .overlay {
                if !isUnlocked {
                    PrivacyShield()
                        .transition(.opacity)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                updateLock(for: newPhase)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                updateLock(for: .inactive)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                updateLock(for: .active)
            }
        }

        private var monthPickerButton: some View {
            Menu {
                Section {
                    if !isCurrentMonth {
                        Button {
                            selectedMonth = Date.now.startOfMonth
                        } label: {
                            Label("Jump to Today", systemImage: "calendar")
                        }
                    }
                }

                Section("Past months") {
                    ForEach(walkableMonths, id: \.self) { month in
                        Button {
                            withAnimation(.snappy(duration: 0.25)) {
                                selectedMonth = month
                            }
                        } label: {
                            if month == selectedMonth {
                                Label(month.formatted(.dateTime.month(.wide).year()), systemImage: "checkmark")
                            } else {
                                Text(month.formatted(.dateTime.month(.wide).year()))
                            }
                        }
                        .disabled(month == selectedMonth)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedMonth.formatted(.dateTime.month(.wide).year()))
                        .font(.headline.monospacedDigit())
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Selected month")
            .accessibilityHint("Opens a list of months to choose from")
        }

        private var isCurrentMonth: Bool {
            Calendar.current.isDate(selectedMonth, equalTo: Date.now.startOfMonth, toGranularity: .month)
        }

        private func showHelpFromToolbar() {
            showHelpSheet = true
        }

        @State private var showHelpSheet = false

        struct MonthPageView: View {
            let month: Date
            @Binding var showAddTransaction: Bool
            @Binding var editingTransaction: Transaction?
            @Binding var hiddenCategoryIDs: Set<Category.ID>
            @Binding var minAmountText: String
            @Binding var maxAmountText: String
            @Binding var showIncome: Bool
            @Binding var showExpense: Bool
            @Binding var showInvestment: Bool

            var body: some View {
                TransactionListView(
                    selectedMonth: month,
                    showAddTransaction: $showAddTransaction,
                    editingTransaction: $editingTransaction,
                    hiddenCategoryIDs: $hiddenCategoryIDs,
                    minAmountText: $minAmountText,
                    maxAmountText: $maxAmountText,
                    showIncome: $showIncome,
                    showExpense: $showExpense,
                    showInvestment: $showInvestment
                ) {
                    WeeklyChartView(
                        selectedMonth: month,
                        hiddenCategoryIDs: hiddenCategoryIDs,
                        minAmount: minAmount,
                        maxAmount: maxAmount,
                        showIncome: showIncome,
                        showExpense: showExpense,
                        showInvestment: showInvestment
                    )
                    .padding(.top, 8)
                }
            }

            private var minAmount: Double? {
                let trimmed = minAmountText.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }
                return Double(trimmed)
            }

            private var maxAmount: Double? {
                let trimmed = maxAmountText.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }
                return Double(trimmed)
            }
        }
    #endif

    #if os(iOS)
        private func updateLock(for phase: ScenePhase) {
            withAnimation(.easeInOut(duration: 0.15)) {
                isUnlocked = phase == .active
            }
        }
    #endif
}
