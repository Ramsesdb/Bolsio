///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

part of 'translations.g.dart';

// Path: <root>
typedef TranslationsEn = Translations; // ignore: unused_element
class Translations with BaseTranslations<AppLocale, Translations> {
	/// Returns the current translations of the given [context].
	///
	/// Usage:
	/// final t = Translations.of(context);
	static Translations of(BuildContext context) => InheritedLocaleData.of<AppLocale, Translations>(context).translations;

	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	Translations({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.en,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ) {
		$meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <en>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	/// Access flat map
	dynamic operator[](String key) => $meta.getTranslation(key);

	late final Translations _root = this; // ignore: unused_field

	Translations $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => Translations(meta: meta ?? this.$meta);

	// Translations
	late final TranslationsUiActionsEn ui_actions = TranslationsUiActionsEn.internal(_root);
	late final TranslationsGeneralEn general = TranslationsGeneralEn.internal(_root);
	late final TranslationsSharedEn shared = TranslationsSharedEn.internal(_root);
	late final TranslationsHomeEn home = TranslationsHomeEn.internal(_root);
	late final TranslationsCalculatorEn calculator = TranslationsCalculatorEn.internal(_root);
	late final TranslationsFinancialHealthEn financial_health = TranslationsFinancialHealthEn.internal(_root);
	late final TranslationsStatsEn stats = TranslationsStatsEn.internal(_root);
	late final TranslationsIconSelectorEn icon_selector = TranslationsIconSelectorEn.internal(_root);
	late final TranslationsTransactionEn transaction = TranslationsTransactionEn.internal(_root);
	late final TranslationsAttachmentsEn attachments = TranslationsAttachmentsEn.internal(_root);
	late final TranslationsBolsioAiEn bolsio_ai = TranslationsBolsioAiEn.internal(_root);
	late final TranslationsTransferEn transfer = TranslationsTransferEn.internal(_root);
	late final TranslationsRecurrentTransactionsEn recurrent_transactions = TranslationsRecurrentTransactionsEn.internal(_root);
	late final TranslationsAccountEn account = TranslationsAccountEn.internal(_root);
	late final TranslationsCurrenciesEn currencies = TranslationsCurrenciesEn.internal(_root);
	late final TranslationsTagsEn tags = TranslationsTagsEn.internal(_root);
	late final TranslationsCategoriesEn categories = TranslationsCategoriesEn.internal(_root);
	late final TranslationsBudgetsEn budgets = TranslationsBudgetsEn.internal(_root);
	late final TranslationsGoalsEn goals = TranslationsGoalsEn.internal(_root);
	late final TranslationsDebtsEn debts = TranslationsDebtsEn.internal(_root);
	late final TranslationsTargetTimelineStatusesEn target_timeline_statuses = TranslationsTargetTimelineStatusesEn.internal(_root);
	late final TranslationsBackupEn backup = TranslationsBackupEn.internal(_root);
	late final TranslationsProfileEn profile = TranslationsProfileEn.internal(_root);
	late final TranslationsSettingsEn settings = TranslationsSettingsEn.internal(_root);
	late final TranslationsStatementImportEn statement_import = TranslationsStatementImportEn.internal(_root);
	late final TranslationsMoreEn more = TranslationsMoreEn.internal(_root);
	late final TranslationsOnboardingEn onboarding = TranslationsOnboardingEn.internal(_root);
}

// Path: ui_actions
class TranslationsUiActionsEn {
	TranslationsUiActionsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Cancel'
	String get cancel => 'Cancel';

	/// en: 'Confirm'
	String get confirm => 'Confirm';

	/// en: 'Continue'
	String get continue_text => 'Continue';

	/// en: 'Save'
	String get save => 'Save';

	/// en: 'Save changes'
	String get save_changes => 'Save changes';

	/// en: 'Save and close'
	String get close_and_save => 'Save and close';

	/// en: 'Add'
	String get add => 'Add';

	/// en: 'Edit'
	String get edit => 'Edit';

	/// en: 'Delete'
	String get delete => 'Delete';

	/// en: 'See more'
	String get see_more => 'See more';

	/// en: 'Select all'
	String get select_all => 'Select all';

	/// en: 'Deselect all'
	String get deselect_all => 'Deselect all';

	/// en: 'Select'
	String get select => 'Select';

	/// en: 'Search'
	String get search => 'Search';

	/// en: 'Filter'
	String get filter => 'Filter';

	/// en: 'Reset'
	String get reset => 'Reset';

	/// en: 'Submit'
	String get submit => 'Submit';

	/// en: 'Next'
	String get next => 'Next';

	/// en: 'Previous'
	String get previous => 'Previous';

	/// en: 'Back'
	String get back => 'Back';

	/// en: 'Reload'
	String get reload => 'Reload';

	/// en: 'View'
	String get view => 'View';

	/// en: 'Download'
	String get download => 'Download';

	/// en: 'Upload'
	String get upload => 'Upload';

	/// en: 'Retry'
	String get retry => 'Retry';

	/// en: 'Copy'
	String get copy => 'Copy';

	/// en: 'Paste'
	String get paste => 'Paste';

	/// en: 'Undo'
	String get undo => 'Undo';

	/// en: 'Redo'
	String get redo => 'Redo';

	/// en: 'Open'
	String get open => 'Open';

	/// en: 'Close'
	String get close => 'Close';

	/// en: 'Apply'
	String get apply => 'Apply';

	/// en: 'Discard'
	String get discard => 'Discard';

	/// en: 'Refresh'
	String get refresh => 'Refresh';

	/// en: 'Share'
	String get share => 'Share';
}

// Path: general
class TranslationsGeneralEn {
	TranslationsGeneralEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'or'
	String get or => 'or';

	/// en: 'Understood'
	String get understood => 'Understood';

	/// en: 'Unspecified'
	String get unspecified => 'Unspecified';

	/// en: 'Quick actions'
	String get quick_actions => 'Quick actions';

	/// en: 'Details'
	String get details => 'Details';

	/// en: 'Balance'
	String get balance => 'Balance';

	/// en: 'Account'
	String get account => 'Account';

	/// en: 'Accounts'
	String get accounts => 'Accounts';

	/// en: 'Categories'
	String get categories => 'Categories';

	/// en: 'Category'
	String get category => 'Category';

	/// en: 'Today'
	String get today => 'Today';

	/// en: 'Yesterday'
	String get yesterday => 'Yesterday';

	/// en: 'Filters'
	String get filters => 'Filters';

	/// en: 'Ops! This is very empty'
	String get empty_warn => 'Ops! This is very empty';

	/// en: 'No items match your search criteria'
	String get search_no_results => 'No items match your search criteria';

	/// en: 'Insufficient data'
	String get insufficient_data => 'Insufficient data';

	/// en: 'Show more fields'
	String get show_more_fields => 'Show more fields';

	/// en: 'Show less fields'
	String get show_less_fields => 'Show less fields';

	/// en: 'Tap to search'
	String get tap_to_search => 'Tap to search';

	/// en: 'Item deleted successfully'
	String get delete_success => 'Item deleted successfully';

	late final TranslationsGeneralLeaveWithoutSavingEn leave_without_saving = TranslationsGeneralLeaveWithoutSavingEn.internal(_root);
	late final TranslationsGeneralClipboardEn clipboard = TranslationsGeneralClipboardEn.internal(_root);
	late final TranslationsGeneralTimeEn time = TranslationsGeneralTimeEn.internal(_root);
	late final TranslationsGeneralTransactionOrderEn transaction_order = TranslationsGeneralTransactionOrderEn.internal(_root);
	late final TranslationsGeneralValidationsEn validations = TranslationsGeneralValidationsEn.internal(_root);
}

// Path: shared
class TranslationsSharedEn {
	TranslationsSharedEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: '100% open, 100% free'
	String get app_tagline => '100% open, 100% free';
}

// Path: home
class TranslationsHomeEn {
	TranslationsHomeEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Dashboard'
	String get title => 'Dashboard';

	/// en: 'Filter transactions'
	String get filter_transactions => 'Filter transactions';

	/// en: 'Good morning,'
	String get hello_day => 'Good morning,';

	/// en: 'Good night,'
	String get hello_night => 'Good night,';

	/// en: 'Total balance'
	String get total_balance => 'Total balance';

	/// en: 'My accounts'
	String get my_accounts => 'My accounts';

	/// en: 'Active accounts'
	String get active_accounts => 'Active accounts';

	/// en: 'No accounts created yet'
	String get no_accounts => 'No accounts created yet';

	/// en: 'Start using all the magic of Bolsio. Create at least one account to start adding transactions'
	String get no_accounts_descr => 'Start using all the magic of Bolsio. Create at least one account to start adding transactions';

	/// en: 'Last transactions'
	String get last_transactions => 'Last transactions';

	/// en: 'Oops!'
	String get should_create_account_header => 'Oops!';

	/// en: 'You must have at least one no-archived account before you can start creating transactions'
	String get should_create_account_message => 'You must have at least one no-archived account before you can start creating transactions';

	late final TranslationsHomeDashboardWidgetsEn dashboard_widgets = TranslationsHomeDashboardWidgetsEn.internal(_root);
	late final TranslationsHomeQuickActionsEn quick_actions = TranslationsHomeQuickActionsEn.internal(_root);
}

// Path: calculator
class TranslationsCalculatorEn {
	TranslationsCalculatorEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Calculator'
	String get title => 'Calculator';

	/// en: 'Quick converter USD/EUR/USDT to VES'
	String get settings_subtitle => 'Quick converter USD/EUR/USDT to VES';

	late final TranslationsCalculatorSwapEn swap = TranslationsCalculatorSwapEn.internal(_root);
	late final TranslationsCalculatorKeypadEn keypad = TranslationsCalculatorKeypadEn.internal(_root);
	late final TranslationsCalculatorSourceEn source = TranslationsCalculatorSourceEn.internal(_root);
	late final TranslationsCalculatorManualEn manual = TranslationsCalculatorManualEn.internal(_root);
	late final TranslationsCalculatorWarnEn warn = TranslationsCalculatorWarnEn.internal(_root);
	late final TranslationsCalculatorRefreshEn refresh = TranslationsCalculatorRefreshEn.internal(_root);
	late final TranslationsCalculatorShareEn share = TranslationsCalculatorShareEn.internal(_root);
	late final TranslationsCalculatorRateExplicitEn rate_explicit = TranslationsCalculatorRateExplicitEn.internal(_root);
	late final TranslationsCalculatorCopyEn copy = TranslationsCalculatorCopyEn.internal(_root);
}

// Path: financial_health
class TranslationsFinancialHealthEn {
	TranslationsFinancialHealthEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Financial health'
	String get display => 'Financial health';

	late final TranslationsFinancialHealthReviewEn review = TranslationsFinancialHealthReviewEn.internal(_root);
	late final TranslationsFinancialHealthMonthsWithoutIncomeEn months_without_income = TranslationsFinancialHealthMonthsWithoutIncomeEn.internal(_root);
	late final TranslationsFinancialHealthSavingsPercentageEn savings_percentage = TranslationsFinancialHealthSavingsPercentageEn.internal(_root);
}

// Path: stats
class TranslationsStatsEn {
	TranslationsStatsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Statistics'
	String get title => 'Statistics';

	/// en: 'Balance'
	String get balance => 'Balance';

	/// en: 'Final balance'
	String get final_balance => 'Final balance';

	/// en: 'Balance by accounts'
	String get balance_by_account => 'Balance by accounts';

	/// en: 'Where do I have most of my money?'
	String get balance_by_account_subtitle => 'Where do I have most of my money?';

	/// en: 'Balance by currency'
	String get balance_by_currency => 'Balance by currency';

	/// en: 'How much money do I have in foreign currency?'
	String get balance_by_currency_subtitle => 'How much money do I have in foreign currency?';

	/// en: 'Balance trend'
	String get balance_evolution => 'Balance trend';

	/// en: 'Do I have more money than before?'
	String get balance_evolution_subtitle => 'Do I have more money than before?';

	/// en: 'Compared to the previous period'
	String get compared_to_previous_period => 'Compared to the previous period';

	/// en: 'Cash flow'
	String get cash_flow => 'Cash flow';

	/// en: 'Am I spending less than I earn?'
	String get cash_flow_subtitle => 'Am I spending less than I earn?';

	/// en: 'By periods'
	String get by_periods => 'By periods';

	/// en: 'By categories'
	String get by_categories => 'By categories';

	/// en: 'By tags'
	String get by_tags => 'By tags';

	/// en: 'Distribution'
	String get distribution => 'Distribution';

	/// en: 'Resume'
	String get finance_health_resume => 'Resume';

	/// en: 'Breakdown'
	String get finance_health_breakdown => 'Breakdown';
}

// Path: icon_selector
class TranslationsIconSelectorEn {
	TranslationsIconSelectorEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Name:'
	String get name => 'Name:';

	/// en: 'Icon'
	String get icon => 'Icon';

	/// en: 'Color'
	String get color => 'Color';

	/// en: 'Select an icon'
	String get select_icon => 'Select an icon';

	/// en: 'Select a color'
	String get select_color => 'Select a color';

	/// en: 'Custom color'
	String get custom_color => 'Custom color';

	/// en: 'Current selection'
	String get current_color_selection => 'Current selection';

	/// en: 'Identify your account'
	String get select_account_icon => 'Identify your account';

	/// en: 'Identify your category'
	String get select_category_icon => 'Identify your category';

	late final TranslationsIconSelectorScopesEn scopes = TranslationsIconSelectorScopesEn.internal(_root);
}

// Path: transaction
class TranslationsTransactionEn {
	TranslationsTransactionEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: '(one) {Transaction} (other) {Transactions}'
	String display({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Transaction',
		other: 'Transactions',
	);

	/// en: 'Select a transaction'
	String get select => 'Select a transaction';

	/// en: 'New transaction'
	String get create => 'New transaction';

	/// en: 'New income'
	String get new_income => 'New income';

	/// en: 'New expense'
	String get new_expense => 'New expense';

	/// en: 'Transaction created successfully'
	String get new_success => 'Transaction created successfully';

	/// en: 'Edit transaction'
	String get edit => 'Edit transaction';

	/// en: 'Transaction edited successfully'
	String get edit_success => 'Transaction edited successfully';

	/// en: 'Edit transactions'
	String get edit_multiple => 'Edit transactions';

	/// en: '{{ x }} transactions edited successfully'
	String edit_multiple_success({required Object x}) => '${x} transactions edited successfully';

	/// en: 'Clone transaction'
	String get duplicate => 'Clone transaction';

	/// en: 'Clone'
	String get duplicate_short => 'Clone';

	/// en: 'A transaction identical to this will be created with the same date, do you want to continue?'
	String get duplicate_warning_message => 'A transaction identical to this will be created with the same date, do you want to continue?';

	/// en: 'Transaction cloned successfully'
	String get duplicate_success => 'Transaction cloned successfully';

	/// en: 'Delete transaction'
	String get delete => 'Delete transaction';

	/// en: 'This action is irreversible. The current balance of your accounts and all your statistics will be recalculated'
	String get delete_warning_message => 'This action is irreversible. The current balance of your accounts and all your statistics will be recalculated';

	/// en: 'Transaction deleted correctly'
	String get delete_success => 'Transaction deleted correctly';

	/// en: 'Delete transactions'
	String get delete_multiple => 'Delete transactions';

	/// en: 'This action is irreversible and will remove {{ x }} transactions. The current balance of your accounts and all your statistics will be recalculated'
	String delete_multiple_warning_message({required Object x}) => 'This action is irreversible and will remove ${x} transactions. The current balance of your accounts and all your statistics will be recalculated';

	/// en: '{{x}} transactions deleted correctly'
	String delete_multiple_success({required Object x}) => '${x} transactions deleted correctly';

	/// en: 'Movement details'
	String get details => 'Movement details';

	/// en: 'Receipt attached'
	String get receipt_attached => 'Receipt attached';

	/// en: 'View receipt'
	String get view_receipt => 'View receipt';

	late final TranslationsTransactionNextPaymentsEn next_payments = TranslationsTransactionNextPaymentsEn.internal(_root);
	late final TranslationsTransactionListEn list = TranslationsTransactionListEn.internal(_root);
	late final TranslationsTransactionFiltersEn filters = TranslationsTransactionFiltersEn.internal(_root);
	late final TranslationsTransactionFormEn form = TranslationsTransactionFormEn.internal(_root);
	late final TranslationsTransactionReceiptImportEn receipt_import = TranslationsTransactionReceiptImportEn.internal(_root);
	late final TranslationsTransactionReversedEn reversed = TranslationsTransactionReversedEn.internal(_root);
	late final TranslationsTransactionStatusEn status = TranslationsTransactionStatusEn.internal(_root);
	late final TranslationsTransactionTypesEn types = TranslationsTransactionTypesEn.internal(_root);
}

// Path: attachments
class TranslationsAttachmentsEn {
	TranslationsAttachmentsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'View attachment'
	String get view => 'View attachment';

	/// en: 'Remove attachment'
	String get remove => 'Remove attachment';

	/// en: 'Replace'
	String get replace => 'Replace';

	/// en: 'Upload from gallery'
	String get upload_from_gallery => 'Upload from gallery';

	/// en: 'Take photo'
	String get upload_from_camera => 'Take photo';

	/// en: 'No attachments'
	String get empty_state => 'No attachments';
}

// Path: bolsio_ai
class TranslationsBolsioAiEn {
	TranslationsBolsioAiEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Voice input'
	String get voice_settings_title => 'Voice input';

	/// en: 'Dictate expenses and ask the assistant'
	String get voice_settings_subtitle => 'Dictate expenses and ask the assistant';

	/// en: 'Microphone access'
	String get voice_permission_title => 'Microphone access';

	/// en: 'Bolsio needs the microphone to transcribe what you dictate and turn it into transactions or questions. Audio is never stored.'
	String get voice_permission_body => 'Bolsio needs the microphone to transcribe what you dictate and turn it into transactions or questions. Audio is never stored.';

	/// en: 'Got it, continue'
	String get voice_permission_cta => 'Got it, continue';

	/// en: 'Microphone permission denied'
	String get voice_permission_denied_title => 'Microphone permission denied';

	/// en: 'To dictate or voice-chat, enable the permission in your system settings.'
	String get voice_permission_denied_body => 'To dictate or voice-chat, enable the permission in your system settings.';

	/// en: 'Microphone permission denied'
	String get voice_permission_denied_snackbar => 'Microphone permission denied';

	/// en: 'Open settings'
	String get voice_permission_open_settings => 'Open settings';

	/// en: 'Check your internet connection to use voice dictation.'
	String get voice_offline_hint => 'Check your internet connection to use voice dictation.';

	/// en: 'Speech recognition isn't available on this device.'
	String get voice_stt_unavailable => 'Speech recognition isn\'t available on this device.';

	/// en: 'I didn't hear anything, try again.'
	String get voice_empty_transcript => 'I didn\'t hear anything, try again.';

	/// en: 'Dictate expense'
	String get voice_fab_tooltip => 'Dictate expense';

	/// en: 'Listening...'
	String get voice_listening_title => 'Listening...';

	/// en: 'Tell me the expense in one phrase.'
	String get voice_listening_subtitle => 'Tell me the expense in one phrase.';

	/// en: 'E.g. "I spent 20 dollars on lunch"'
	String get voice_listening_hint => 'E.g. "I spent 20 dollars on lunch"';

	/// en: 'Something went wrong'
	String get voice_error_title => 'Something went wrong';

	/// en: 'Recognition error'
	String get voice_error_fallback => 'Recognition error';

	/// en: 'Cancel'
	String get voice_cancel => 'Cancel';

	/// en: 'Done'
	String get voice_done => 'Done';

	/// en: 'Retry'
	String get voice_retry => 'Retry';

	/// en: 'Processing...'
	String get voice_processing => 'Processing...';

	/// en: 'New voice transaction'
	String get voice_review_title => 'New voice transaction';

	/// en: 'Tap to edit'
	String get voice_review_tap_to_edit => 'Tap to edit';

	/// en: 'Account'
	String get voice_review_account_label => 'Account';

	/// en: 'Auto {{seconds}}s'
	String voice_review_auto_countdown({required Object seconds}) => 'Auto ${seconds}s';

	/// en: 'Save'
	String get voice_review_save => 'Save';

	/// en: 'Edit more'
	String get voice_review_edit_more => 'Edit more';

	/// en: 'Description'
	String get voice_review_description_placeholder => 'Description';

	/// en: 'Amount'
	String get voice_review_amount_placeholder => 'Amount';

	/// en: 'Category'
	String get voice_review_category_placeholder => 'Category';

	/// en: 'No category'
	String get voice_review_category_none => 'No category';

	/// en: 'Date'
	String get voice_review_date_placeholder => 'Date';

	/// en: 'Today'
	String get voice_review_date_today => 'Today';

	/// en: 'Select account'
	String get voice_review_account_placeholder => 'Select account';

	/// en: 'What was it for...?'
	String get voice_review_description_hint => 'What was it for...?';

	/// en: 'Expense saved'
	String get voice_save_success_auto => 'Expense saved';

	/// en: 'Done, saved.'
	String get voice_save_success_manual => 'Done, saved.';

	/// en: 'Undo'
	String get voice_save_undo_label => 'Undo';

	/// en: 'Deleted'
	String get voice_save_undo_success => 'Deleted';

	/// en: 'Add an amount greater than 0 to continue.'
	String get voice_validation_amount_zero => 'Add an amount greater than 0 to continue.';

	/// en: 'Select an account.'
	String get voice_validation_account_missing => 'Select an account.';

	/// en: 'Select a category.'
	String get voice_validation_category_missing => 'Select a category.';

	/// en: 'I couldn't extract an expense from what you said.'
	String get voice_flow_no_proposal => 'I couldn\'t extract an expense from what you said.';

	/// en: 'I couldn't interpret that'
	String get voice_flow_error_title => 'I couldn\'t interpret that';

	/// en: 'AI service unavailable'
	String get voice_flow_gateway_unavailable_title => 'AI service unavailable';

	/// en: 'The AI service is not available. Please try again in a moment.'
	String get voice_flow_gateway_unavailable => 'The AI service is not available. Please try again in a moment.';

	/// en: 'Ask about your finances...'
	String get chat_input_hint_default => 'Ask about your finances...';

	/// en: 'Looking up your data...'
	String get chat_input_hint_using_tools => 'Looking up your data...';

	/// en: 'I couldn't process your question, try again.'
	String get chat_error_generic => 'I couldn\'t process your question, try again.';

	/// en: 'I couldn't complete the query.'
	String get chat_error_loop_cap => 'I couldn\'t complete the query.';

	/// en: 'Create expense'
	String get chat_tool_create_transaction_expense => 'Create expense';

	/// en: 'Register income'
	String get chat_tool_create_transaction_income => 'Register income';

	/// en: 'Create transfer'
	String get chat_tool_create_transfer => 'Create transfer';

	/// en: 'Confirm action'
	String get chat_tool_generic_confirm => 'Confirm action';

	/// en: 'Check the details before confirming.'
	String get chat_tool_review_subtitle => 'Check the details before confirming.';

	/// en: 'No details available.'
	String get chat_tool_no_details => 'No details available.';

	/// en: 'Approve and run'
	String get chat_tool_cta_approve => 'Approve and run';

	/// en: 'Cancel'
	String get chat_tool_cta_cancel => 'Cancel';

	/// en: 'Amount'
	String get chat_tool_field_amount => 'Amount';

	/// en: 'Type'
	String get chat_tool_field_type => 'Type';

	/// en: 'Income'
	String get chat_tool_field_type_income => 'Income';

	/// en: 'Expense'
	String get chat_tool_field_type_expense => 'Expense';

	/// en: 'Description'
	String get chat_tool_field_description => 'Description';

	/// en: 'Category'
	String get chat_tool_field_category => 'Category';

	/// en: 'Account'
	String get chat_tool_field_account => 'Account';

	/// en: 'Date'
	String get chat_tool_field_date => 'Date';

	/// en: 'From'
	String get chat_tool_field_from_account => 'From';

	/// en: 'To'
	String get chat_tool_field_to_account => 'To';

	/// en: 'Destination amount'
	String get chat_tool_field_value_in_destiny => 'Destination amount';

	/// en: 'Bolsi'
	String get chat_header => 'Bolsi';

	/// en: 'Loading financial context...'
	String get chat_boot_loading => 'Loading financial context...';

	/// en: 'AI chat is disabled in settings.'
	String get chat_disabled => 'AI chat is disabled in settings.';

	/// en: 'Hi! I'm Bolsi 👛 your pocket buddy. How can I help today?'
	String get chat_welcome_message => 'Hi! I\'m Bolsi 👛 your pocket buddy. How can I help today?';
}

// Path: transfer
class TranslationsTransferEn {
	TranslationsTransferEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Transfer'
	String get display => 'Transfer';

	/// en: 'Transfers'
	String get transfers => 'Transfers';

	/// en: 'Transfer to {{ account }}'
	String transfer_to({required Object account}) => 'Transfer to ${account}';

	/// en: 'New Transfer'
	String get create => 'New Transfer';

	/// en: 'Ops!'
	String get need_two_accounts_warning_header => 'Ops!';

	/// en: 'At least two accounts are needed to perform this action. If you need to adjust or edit the current balance of this account, click the edit button'
	String get need_two_accounts_warning_message => 'At least two accounts are needed to perform this action. If you need to adjust or edit the current balance of this account, click the edit button';

	late final TranslationsTransferFormEn form = TranslationsTransferFormEn.internal(_root);
}

// Path: recurrent_transactions
class TranslationsRecurrentTransactionsEn {
	TranslationsRecurrentTransactionsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Recurrent transactions'
	String get title => 'Recurrent transactions';

	/// en: 'Rec. transactions'
	String get title_short => 'Rec. transactions';

	/// en: 'It looks like you don't have any recurring transactions. Create a monthly, yearly, or weekly recurring transaction and it will appear here'
	String get empty => 'It looks like you don\'t have any recurring transactions. Create a monthly, yearly, or weekly recurring transaction and it will appear here';

	/// en: 'Total expense per period'
	String get total_expense_title => 'Total expense per period';

	/// en: '* Without considering the start and end date of each recurrence'
	String get total_expense_descr => '* Without considering the start and end date of each recurrence';

	late final TranslationsRecurrentTransactionsDetailsEn details = TranslationsRecurrentTransactionsDetailsEn.internal(_root);
	late final TranslationsRecurrentTransactionsStatusEn status = TranslationsRecurrentTransactionsStatusEn.internal(_root);
}

// Path: account
class TranslationsAccountEn {
	TranslationsAccountEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Account details'
	String get details => 'Account details';

	/// en: 'Opening date'
	String get date => 'Opening date';

	/// en: 'Closing date'
	String get close_date => 'Closing date';

	/// en: 'Re-open account'
	String get reopen => 'Re-open account';

	/// en: 'Re-open'
	String get reopen_short => 'Re-open';

	/// en: 'Are you sure you want to reopen this account?'
	String get reopen_descr => 'Are you sure you want to reopen this account?';

	/// en: 'Account balance'
	String get balance => 'Account balance';

	/// en: 'Number of transactions'
	String get n_transactions => 'Number of transactions';

	/// en: 'Add money'
	String get add_money => 'Add money';

	/// en: 'Withdraw money'
	String get withdraw_money => 'Withdraw money';

	/// en: 'No accounts found to display here. Add an account by clicking the '+' button at the bottom'
	String get no_accounts => 'No accounts found to display here. Add an account by clicking the \'+\' button at the bottom';

	late final TranslationsAccountTypesEn types = TranslationsAccountTypesEn.internal(_root);
	late final TranslationsAccountFormEn form = TranslationsAccountFormEn.internal(_root);
	late final TranslationsAccountBadgeEn badge = TranslationsAccountBadgeEn.internal(_root);
	late final TranslationsAccountRetroactiveEn retroactive = TranslationsAccountRetroactiveEn.internal(_root);
	late final TranslationsAccountDeleteEn delete = TranslationsAccountDeleteEn.internal(_root);
	late final TranslationsAccountCloseEn close = TranslationsAccountCloseEn.internal(_root);
	late final TranslationsAccountSelectEn select = TranslationsAccountSelectEn.internal(_root);
}

// Path: currencies
class TranslationsCurrenciesEn {
	TranslationsCurrenciesEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Currency converter'
	String get currency_converter => 'Currency converter';

	/// en: 'Currency'
	String get currency => 'Currency';

	/// en: 'Currency settings'
	String get currency_settings => 'Currency settings';

	/// en: 'Currency manager'
	String get currency_manager => 'Currency manager';

	/// en: 'Configure your currency and its exchange rates with others'
	String get currency_manager_descr => 'Configure your currency and its exchange rates with others';

	/// en: 'Preferred/base currency'
	String get preferred_currency => 'Preferred/base currency';

	/// en: 'Tap to change'
	String get tap_to_change_preferred_currency => 'Tap to change';

	/// en: 'Change preferred currency'
	String get change_preferred_currency_title => 'Change preferred currency';

	/// en: 'All stats and budgets will be displayed in this currency from now on. Accounts and transactions will keep the currency they had. All saved exchange rates will be deleted if you execute this action. Do you wish to continue?'
	String get change_preferred_currency_msg => 'All stats and budgets will be displayed in this currency from now on. Accounts and transactions will keep the currency they had. All saved exchange rates will be deleted if you execute this action. Do you wish to continue?';

	late final TranslationsCurrenciesExchangeRateFormEn exchange_rate_form = TranslationsCurrenciesExchangeRateFormEn.internal(_root);
	late final TranslationsCurrenciesTypesEn types = TranslationsCurrenciesTypesEn.internal(_root);
	late final TranslationsCurrenciesCurrencyFormEn currency_form = TranslationsCurrenciesCurrencyFormEn.internal(_root);

	/// en: 'Deleted exchange rates successfully'
	String get delete_all_success => 'Deleted exchange rates successfully';

	/// en: 'Historical rates'
	String get historical => 'Historical rates';

	/// en: 'No historical exchange rates found for this currency'
	String get historical_empty => 'No historical exchange rates found for this currency';

	/// en: 'Exchange rate'
	String get exchange_rate => 'Exchange rate';

	/// en: 'Exchange rates'
	String get exchange_rates => 'Exchange rates';

	/// en: 'Minimum exchange rate'
	String get min_exchange_rate => 'Minimum exchange rate';

	/// en: 'Maximum exchange rate'
	String get max_exchange_rate => 'Maximum exchange rate';

	/// en: 'Add exchange rates here so that if you have accounts in currencies other than your base currency our charts are more accurate'
	String get empty => 'Add exchange rates here so that if you have accounts in currencies other than your base currency our charts are more accurate';

	/// en: 'Select a currency'
	String get select_a_currency => 'Select a currency';

	/// en: 'Search by name or by currency code'
	String get search => 'Search by name or by currency code';
}

// Path: tags
class TranslationsTagsEn {
	TranslationsTagsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: '(one) {Label} (other) {Tags}'
	String display({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Label',
		other: 'Tags',
	);

	late final TranslationsTagsFormEn form = TranslationsTagsFormEn.internal(_root);
	late final TranslationsTagsSelectEn select = TranslationsTagsSelectEn.internal(_root);

	/// en: 'You haven't created any tags yet. Tags and categories are a great way to categorize your movements'
	String get empty_list => 'You haven\'t created any tags yet. Tags and categories are a great way to categorize your movements';

	/// en: 'Without tags'
	String get without_tags => 'Without tags';

	/// en: 'Add tag'
	String get add => 'Add tag';

	/// en: 'Create label'
	String get create => 'Create label';

	/// en: 'Label created successfully'
	String get create_success => 'Label created successfully';

	/// en: 'This tag name already exists. You may want to edit it'
	String get already_exists => 'This tag name already exists. You may want to edit it';

	/// en: 'Edit tag'
	String get edit => 'Edit tag';

	/// en: 'Tag edited successfully'
	String get edit_success => 'Tag edited successfully';

	/// en: 'Category deleted successfully'
	String get delete_success => 'Category deleted successfully';

	/// en: 'Delete tag?'
	String get delete_warning_header => 'Delete tag?';

	/// en: 'This action will not delete transactions that have this tag.'
	String get delete_warning_message => 'This action will not delete transactions that have this tag.';
}

// Path: categories
class TranslationsCategoriesEn {
	TranslationsCategoriesEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Unknown category'
	String get unknown => 'Unknown category';

	/// en: 'Create category'
	String get create => 'Create category';

	/// en: 'Category created correctly'
	String get create_success => 'Category created correctly';

	/// en: 'New category'
	String get new_category => 'New category';

	/// en: 'The name of this category already exists. Maybe you want to edit it'
	String get already_exists => 'The name of this category already exists. Maybe you want to edit it';

	/// en: 'Edit category'
	String get edit => 'Edit category';

	/// en: 'Category edited correctly'
	String get edit_success => 'Category edited correctly';

	/// en: 'Category name'
	String get name => 'Category name';

	/// en: 'Category type'
	String get type => 'Category type';

	/// en: 'Both types'
	String get both_types => 'Both types';

	/// en: 'Subcategories'
	String get subcategories => 'Subcategories';

	/// en: 'Add subcategory'
	String get subcategories_add => 'Add subcategory';

	/// en: 'Make to category'
	String get make_parent => 'Make to category';

	/// en: 'Make a subcategory'
	String get make_child => 'Make a subcategory';

	/// en: 'This category and its subcategories will become subcategories of <b>{{destiny}}</b>.'
	String make_child_warning1({required Object destiny}) => 'This category and its subcategories will become subcategories of <b>${destiny}</b>.';

	/// en: 'Their transactions <b>({{x}})</b> will be moved to the new subcategories created within the <b>{{destiny}}</b> category.'
	String make_child_warning2({required Object x, required Object destiny}) => 'Their transactions <b>(${x})</b> will be moved to the new subcategories created within the <b>${destiny}</b> category.';

	/// en: 'Subcategories created successfully'
	String get make_child_success => 'Subcategories created successfully';

	/// en: 'Merge with another category'
	String get merge => 'Merge with another category';

	/// en: 'All transactions ({{x}}) associated with the category <b>{{from}}</b> will be moved to the category <b>{{destiny}}</b>'
	String merge_warning1({required Object x, required Object from, required Object destiny}) => 'All transactions (${x}) associated with the category <b>${from}</b> will be moved to the category <b>${destiny}</b>';

	/// en: 'The category <b>{{from}}</b> will be irreversibly deleted.'
	String merge_warning2({required Object from}) => 'The category <b>${from}</b> will be irreversibly deleted.';

	/// en: 'Category merged successfully'
	String get merge_success => 'Category merged successfully';

	/// en: 'Category deleted correctly'
	String get delete_success => 'Category deleted correctly';

	/// en: 'Delete category?'
	String get delete_warning_header => 'Delete category?';

	/// en: 'This action will irreversibly delete all transactions <b>({{x}})</b> related to this category.'
	String delete_warning_message({required Object x}) => 'This action will irreversibly delete all transactions <b>(${x})</b> related to this category.';

	late final TranslationsCategoriesSelectEn select = TranslationsCategoriesSelectEn.internal(_root);
}

// Path: budgets
class TranslationsBudgetsEn {
	TranslationsBudgetsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Budgets'
	String get title => 'Budgets';

	/// en: 'Budget status'
	String get status => 'Budget status';

	/// en: 'Recurring'
	String get repeated => 'Recurring';

	/// en: 'Once'
	String get one_time => 'Once';

	/// en: 'Actives'
	String get actives => 'Actives';

	/// en: 'left of '
	String get from_budgeted => 'left of ';

	/// en: 'days left'
	String get days_left => 'days left';

	/// en: 'days to start'
	String get days_to_start => 'days to start';

	/// en: 'days since expiration'
	String get since_expiration => 'days since expiration';

	/// en: 'There seem to be no budgets to display in this section. Start by creating a budget by clicking the button below'
	String get no_budgets => 'There seem to be no budgets to display in this section. Start by creating a budget by clicking the button below';

	/// en: 'Delete budget'
	String get delete => 'Delete budget';

	/// en: 'This action is irreversible. Categories and transactions referring to this quote will not be deleted'
	String get delete_warning => 'This action is irreversible. Categories and transactions referring to this quote will not be deleted';

	late final TranslationsBudgetsFormEn form = TranslationsBudgetsFormEn.internal(_root);
	late final TranslationsBudgetsDetailsEn details = TranslationsBudgetsDetailsEn.internal(_root);
	late final TranslationsBudgetsTargetTimelineStatusesEn target_timeline_statuses = TranslationsBudgetsTargetTimelineStatusesEn.internal(_root);
	late final TranslationsBudgetsProgressEn progress = TranslationsBudgetsProgressEn.internal(_root);
}

// Path: goals
class TranslationsGoalsEn {
	TranslationsGoalsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Goals'
	String get title => 'Goals';

	/// en: 'Goal status'
	String get status => 'Goal status';

	late final TranslationsGoalsTypeEn type = TranslationsGoalsTypeEn.internal(_root);

	/// en: 'No goals found'
	String get empty_title => 'No goals found';

	/// en: 'Create a new goal to start tracking your savings!'
	String get empty_description => 'Create a new goal to start tracking your savings!';

	/// en: 'Delete goal'
	String get delete => 'Delete goal';

	/// en: 'This action is irreversible. Categories and transactions referring to this goal will not be deleted'
	String get delete_warning => 'This action is irreversible. Categories and transactions referring to this goal will not be deleted';

	late final TranslationsGoalsFormEn form = TranslationsGoalsFormEn.internal(_root);
	late final TranslationsGoalsDetailsEn details = TranslationsGoalsDetailsEn.internal(_root);
	late final TranslationsGoalsTargetTimelineStatusesEn target_timeline_statuses = TranslationsGoalsTargetTimelineStatusesEn.internal(_root);
	late final TranslationsGoalsProgressEn progress = TranslationsGoalsProgressEn.internal(_root);
}

// Path: debts
class TranslationsDebtsEn {
	TranslationsDebtsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: '(one) {Debt} (other) {Debts}'
	String display({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Debt',
		other: 'Debts',
	);

	late final TranslationsDebtsFormEn form = TranslationsDebtsFormEn.internal(_root);
	late final TranslationsDebtsDirectionEn direction = TranslationsDebtsDirectionEn.internal(_root);
	late final TranslationsDebtsStatusEn status = TranslationsDebtsStatusEn.internal(_root);
	late final TranslationsDebtsDetailsEn details = TranslationsDebtsDetailsEn.internal(_root);
	late final TranslationsDebtsEmptyEn empty = TranslationsDebtsEmptyEn.internal(_root);
	late final TranslationsDebtsActionsEn actions = TranslationsDebtsActionsEn.internal(_root);
}

// Path: target_timeline_statuses
class TranslationsTargetTimelineStatusesEn {
	TranslationsTargetTimelineStatusesEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Active'
	String get active => 'Active';

	/// en: 'Finished'
	String get past => 'Finished';

	/// en: 'Future'
	String get future => 'Future';
}

// Path: backup
class TranslationsBackupEn {
	TranslationsBackupEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'No file selected'
	String get no_file_selected => 'No file selected';

	/// en: 'No directory selected'
	String get no_directory_selected => 'No directory selected';

	late final TranslationsBackupExportEn export = TranslationsBackupExportEn.internal(_root);
	late final TranslationsBackupImportEn import = TranslationsBackupImportEn.internal(_root);
	late final TranslationsBackupAboutEn about = TranslationsBackupAboutEn.internal(_root);
}

// Path: profile
class TranslationsProfileEn {
	TranslationsProfileEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Your avatar'
	String get your_avatar => 'Your avatar';

	/// en: 'Upload photo'
	String get upload_photo => 'Upload photo';

	/// en: 'Replace'
	String get replace_photo => 'Replace';

	/// en: 'Your photo'
	String get your_photo_badge => 'Your photo';

	/// en: 'Your visible name'
	String get name_label => 'Your visible name';

	/// en: '{{count}} options'
	String options_count({required Object count}) => '${count} options';
}

// Path: settings
class TranslationsSettingsEn {
	TranslationsSettingsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Settings & Customization'
	String get title_long => 'Settings & Customization';

	/// en: 'Settings'
	String get title_short => 'Settings';

	/// en: 'Theme, Language, Data and more'
	String get description => 'Theme, Language, Data and more';

	/// en: 'Edit profile'
	String get edit_profile => 'Edit profile';

	late final TranslationsSettingsGeneralEn general = TranslationsSettingsGeneralEn.internal(_root);
	late final TranslationsSettingsSecurityEn security = TranslationsSettingsSecurityEn.internal(_root);
	late final TranslationsSettingsHiddenModeEn hidden_mode = TranslationsSettingsHiddenModeEn.internal(_root);
	late final TranslationsSettingsTransactionsEn transactions = TranslationsSettingsTransactionsEn.internal(_root);
	late final TranslationsSettingsAutoImportEn auto_import = TranslationsSettingsAutoImportEn.internal(_root);
	late final TranslationsSettingsAppearanceEn appearance = TranslationsSettingsAppearanceEn.internal(_root);
}

// Path: statement_import
class TranslationsStatementImportEn {
	TranslationsStatementImportEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Import account statement'
	String get title => 'Import account statement';

	/// en: 'We will process the movements with AI'
	String get subtitle => 'We will process the movements with AI';

	/// en: 'Private AI · your infrastructure'
	String get ai_badge => 'Private AI · your infrastructure';

	late final TranslationsStatementImportCaptureEn capture = TranslationsStatementImportCaptureEn.internal(_root);
	late final TranslationsStatementImportProcessingEn processing = TranslationsStatementImportProcessingEn.internal(_root);
	late final TranslationsStatementImportReviewEn review = TranslationsStatementImportReviewEn.internal(_root);
	late final TranslationsStatementImportModesEn modes = TranslationsStatementImportModesEn.internal(_root);
	late final TranslationsStatementImportConfirmEn confirm = TranslationsStatementImportConfirmEn.internal(_root);
	late final TranslationsStatementImportSuccessEn success = TranslationsStatementImportSuccessEn.internal(_root);
	late final TranslationsStatementImportUndoEn undo = TranslationsStatementImportUndoEn.internal(_root);

	/// en: 'Import account statement'
	String get entry_point => 'Import account statement';
}

// Path: more
class TranslationsMoreEn {
	TranslationsMoreEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'More'
	String get title => 'More';

	/// en: 'More actions'
	String get title_long => 'More actions';

	late final TranslationsMoreSearchEn search = TranslationsMoreSearchEn.internal(_root);
	late final TranslationsMoreSectionsEn sections = TranslationsMoreSectionsEn.internal(_root);
	late final TranslationsMoreAccountEn account = TranslationsMoreAccountEn.internal(_root);
	late final TranslationsMoreThemeEn theme = TranslationsMoreThemeEn.internal(_root);
	late final TranslationsMoreAiEn ai = TranslationsMoreAiEn.internal(_root);
	late final TranslationsMoreDataEn data = TranslationsMoreDataEn.internal(_root);
	late final TranslationsMoreAboutUsEn about_us = TranslationsMoreAboutUsEn.internal(_root);
	late final TranslationsMoreHelpUsEn help_us = TranslationsMoreHelpUsEn.internal(_root);
}

// Path: onboarding
class TranslationsOnboardingEn {
	TranslationsOnboardingEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final TranslationsOnboardingRestrictedSettingsEn restricted_settings = TranslationsOnboardingRestrictedSettingsEn.internal(_root);
}

// Path: general.leave_without_saving
class TranslationsGeneralLeaveWithoutSavingEn {
	TranslationsGeneralLeaveWithoutSavingEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Leave without saving?'
	String get title => 'Leave without saving?';

	/// en: 'You have unsaved changes, are you sure you want to leave without saving them?'
	String get message => 'You have unsaved changes, are you sure you want to leave without saving them?';
}

// Path: general.clipboard
class TranslationsGeneralClipboardEn {
	TranslationsGeneralClipboardEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: '{{x}} copied to the clipboard'
	String success({required Object x}) => '${x} copied to the clipboard';

	/// en: 'Error copying'
	String get error => 'Error copying';
}

// Path: general.time
class TranslationsGeneralTimeEn {
	TranslationsGeneralTimeEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Start date'
	String get start_date => 'Start date';

	/// en: 'End date'
	String get end_date => 'End date';

	/// en: 'From date'
	String get from_date => 'From date';

	/// en: 'Until date'
	String get until_date => 'Until date';

	/// en: 'Date'
	String get date => 'Date';

	/// en: 'Datetime'
	String get datetime => 'Datetime';

	/// en: 'Time'
	String get time => 'Time';

	/// en: 'Each'
	String get each => 'Each';

	/// en: 'After'
	String get after => 'After';

	late final TranslationsGeneralTimeRangesEn ranges = TranslationsGeneralTimeRangesEn.internal(_root);
	late final TranslationsGeneralTimePeriodicityEn periodicity = TranslationsGeneralTimePeriodicityEn.internal(_root);
	late final TranslationsGeneralTimeCurrentEn current = TranslationsGeneralTimeCurrentEn.internal(_root);
	late final TranslationsGeneralTimeAllEn all = TranslationsGeneralTimeAllEn.internal(_root);
}

// Path: general.transaction_order
class TranslationsGeneralTransactionOrderEn {
	TranslationsGeneralTransactionOrderEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Order transactions'
	String get display => 'Order transactions';

	/// en: 'By category'
	String get category => 'By category';

	/// en: 'By quantity'
	String get quantity => 'By quantity';

	/// en: 'By date'
	String get date => 'By date';
}

// Path: general.validations
class TranslationsGeneralValidationsEn {
	TranslationsGeneralValidationsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Fix the indicated fields to continue'
	String get form_error => 'Fix the indicated fields to continue';

	/// en: 'Required field'
	String get required => 'Required field';

	/// en: 'Should be positive'
	String get positive => 'Should be positive';

	/// en: 'Should be greater than {{x}}'
	String min_number({required Object x}) => 'Should be greater than ${x}';

	/// en: 'Should be less than {{x}}'
	String max_number({required Object x}) => 'Should be less than ${x}';
}

// Path: home.dashboard_widgets
class TranslationsHomeDashboardWidgetsEn {
	TranslationsHomeDashboardWidgetsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Long-press to reorder · X to remove · + to add'
	String get edit_banner => 'Long-press to reorder · X to remove · + to add';

	/// en: 'Exit edit mode'
	String get exit_edit_mode => 'Exit edit mode';

	/// en: 'Edit dashboard'
	String get edit_dashboard => 'Edit dashboard';

	/// en: 'Remove widget'
	String get remove_widget_title => 'Remove widget';

	/// en: 'Remove "{name}" from your dashboard?'
	String get remove_widget_message => 'Remove "{name}" from your dashboard?';

	/// en: 'Add widget'
	String get add_widget => 'Add widget';

	/// en: 'Recommended'
	String get recommended_badge => 'Recommended';

	/// en: 'Reset to my goals'
	String get reset_to_goals_action => 'Reset to my goals';

	/// en: 'Reset dashboard?'
	String get reset_to_goals_confirm_title => 'Reset dashboard?';

	/// en: 'Replace your current dashboard with the layout suggested by your onboarding goals.'
	String get reset_to_goals_confirm_message => 'Replace your current dashboard with the layout suggested by your onboarding goals.';

	/// en: 'Long-press to reorder'
	String get drag_handle_tooltip => 'Long-press to reorder';

	/// en: 'Configure'
	String get configure_tooltip => 'Configure';

	/// en: 'Remove'
	String get remove_tooltip => 'Remove';

	late final TranslationsHomeDashboardWidgetsTotalBalanceSummaryEn total_balance_summary = TranslationsHomeDashboardWidgetsTotalBalanceSummaryEn.internal(_root);
	late final TranslationsHomeDashboardWidgetsAccountCarouselEn account_carousel = TranslationsHomeDashboardWidgetsAccountCarouselEn.internal(_root);
	late final TranslationsHomeDashboardWidgetsIncomeExpensePeriodEn income_expense_period = TranslationsHomeDashboardWidgetsIncomeExpensePeriodEn.internal(_root);
	late final TranslationsHomeDashboardWidgetsRecentTransactionsEn recent_transactions = TranslationsHomeDashboardWidgetsRecentTransactionsEn.internal(_root);
	late final TranslationsHomeDashboardWidgetsExchangeRateCardEn exchange_rate_card = TranslationsHomeDashboardWidgetsExchangeRateCardEn.internal(_root);
	late final TranslationsHomeDashboardWidgetsQuickUseEn quick_use = TranslationsHomeDashboardWidgetsQuickUseEn.internal(_root);
	late final TranslationsHomeDashboardWidgetsPendingImportsAlertEn pending_imports_alert = TranslationsHomeDashboardWidgetsPendingImportsAlertEn.internal(_root);
}

// Path: home.quick_actions
class TranslationsHomeQuickActionsEn {
	TranslationsHomeQuickActionsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Private mode'
	String get toggle_private_mode => 'Private mode';

	/// en: 'Hidden mode'
	String get toggle_hidden_mode => 'Hidden mode';

	/// en: 'Currency'
	String get toggle_preferred_currency => 'Currency';

	/// en: 'Settings'
	String get go_to_settings => 'Settings';

	/// en: 'New expense'
	String get new_expense_transaction => 'New expense';

	/// en: 'New income'
	String get new_income_transaction => 'New income';

	/// en: 'Transfer'
	String get new_transfer_transaction => 'Transfer';

	/// en: 'Budgets'
	String get go_to_budgets => 'Budgets';

	/// en: 'Reports'
	String get go_to_reports => 'Reports';

	/// en: 'Transactions'
	String get open_transactions => 'Transactions';

	/// en: 'Exchange rates'
	String get open_exchange_rates => 'Exchange rates';

	/// en: 'Calculator'
	String get go_to_calculator => 'Calculator';
}

// Path: calculator.swap
class TranslationsCalculatorSwapEn {
	TranslationsCalculatorSwapEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Invert conversion'
	String get a11y => 'Invert conversion';
}

// Path: calculator.keypad
class TranslationsCalculatorKeypadEn {
	TranslationsCalculatorKeypadEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final TranslationsCalculatorKeypadA11yEn a11y = TranslationsCalculatorKeypadA11yEn.internal(_root);
}

// Path: calculator.source
class TranslationsCalculatorSourceEn {
	TranslationsCalculatorSourceEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'BCV'
	String get bcv => 'BCV';

	/// en: 'Parallel'
	String get paralelo => 'Parallel';

	/// en: 'Average'
	String get promedio => 'Average';

	/// en: 'Manual'
	String get manual => 'Manual';

	/// en: 'Parallel (USDT)'
	String get usdt_label => 'Parallel (USDT)';

	/// en: '{{minutes}} min ago'
	String updated_ago({required Object minutes}) => '${minutes} min ago';

	/// en: 'just now'
	String get updated_just_now => 'just now';

	/// en: '—'
	String get updated_unknown => '—';

	/// en: 'Rate source: {{source}}, updated {{age}}'
	String a11y_label({required Object source, required Object age}) => 'Rate source: ${source}, updated ${age}';
}

// Path: calculator.manual
class TranslationsCalculatorManualEn {
	TranslationsCalculatorManualEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Rate per 1 {{currency}}'
	String field_hint({required Object currency}) => 'Rate per 1 ${currency}';

	/// en: 'Manual rate'
	String get field_label => 'Manual rate';

	/// en: 'Enter a value greater than 0'
	String get field_invalid => 'Enter a value greater than 0';

	/// en: 'Save as manual rate'
	String get save_link => 'Save as manual rate';
}

// Path: calculator.warn
class TranslationsCalculatorWarnEn {
	TranslationsCalculatorWarnEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'No cached rate. Use manual mode or connect to the internet.'
	String get no_rate => 'No cached rate. Use manual mode or connect to the internet.';
}

// Path: calculator.refresh
class TranslationsCalculatorRefreshEn {
	TranslationsCalculatorRefreshEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Refresh rates'
	String get a11y => 'Refresh rates';

	/// en: 'Could not update rates. Showing cached values.'
	String get error => 'Could not update rates. Showing cached values.';
}

// Path: calculator.share
class TranslationsCalculatorShareEn {
	TranslationsCalculatorShareEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Share conversion'
	String get action_a11y => 'Share conversion';

	/// en: 'Generated with Bolsio'
	String get footer => 'Generated with Bolsio';

	/// en: 'FX conversion'
	String get subject => 'FX conversion';

	/// en: '='
	String get equals_separator => '=';
}

// Path: calculator.rate_explicit
class TranslationsCalculatorRateExplicitEn {
	TranslationsCalculatorRateExplicitEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: '{{from}} 1 = {{to}} {{amount}}'
	String format({required Object from, required Object to, required Object amount}) => '${from} 1 = ${to} ${amount}';

	/// en: 'Updated {{date}}'
	String timestamp_long({required Object date}) => 'Updated ${date}';

	/// en: 'No rate available'
	String get timestamp_unknown => 'No rate available';

	/// en: 'Manual rate'
	String get timestamp_manual => 'Manual rate';
}

// Path: calculator.copy
class TranslationsCalculatorCopyEn {
	TranslationsCalculatorCopyEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Copy'
	String get tooltip => 'Copy';

	/// en: 'Copy amount'
	String get a11y => 'Copy amount';

	/// en: '{{value}} copied'
	String snackbar({required Object value}) => '${value} copied';
}

// Path: financial_health.review
class TranslationsFinancialHealthReviewEn {
	TranslationsFinancialHealthReviewEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: '(male) {Very good!} (female) {Very good!}'
	String very_good({required GenderContext context}) {
		switch (context) {
			case GenderContext.male:
				return 'Very good!';
			case GenderContext.female:
				return 'Very good!';
		}
	}

	/// en: '(male) {Good} (female) {Good}'
	String good({required GenderContext context}) {
		switch (context) {
			case GenderContext.male:
				return 'Good';
			case GenderContext.female:
				return 'Good';
		}
	}

	/// en: '(male) {Average} (female) {Average}'
	String normal({required GenderContext context}) {
		switch (context) {
			case GenderContext.male:
				return 'Average';
			case GenderContext.female:
				return 'Average';
		}
	}

	/// en: '(male) {Fair} (female) {Fair}'
	String bad({required GenderContext context}) {
		switch (context) {
			case GenderContext.male:
				return 'Fair';
			case GenderContext.female:
				return 'Fair';
		}
	}

	/// en: '(male) {Very Bad} (female) {Very Bad}'
	String very_bad({required GenderContext context}) {
		switch (context) {
			case GenderContext.male:
				return 'Very Bad';
			case GenderContext.female:
				return 'Very Bad';
		}
	}

	/// en: '(male) {Insufficient data} (female) {Insufficient data}'
	String insufficient_data({required GenderContext context}) {
		switch (context) {
			case GenderContext.male:
				return 'Insufficient data';
			case GenderContext.female:
				return 'Insufficient data';
		}
	}

	late final TranslationsFinancialHealthReviewDescrEn descr = TranslationsFinancialHealthReviewDescrEn.internal(_root);
}

// Path: financial_health.months_without_income
class TranslationsFinancialHealthMonthsWithoutIncomeEn {
	TranslationsFinancialHealthMonthsWithoutIncomeEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Survival rate'
	String get title => 'Survival rate';

	/// en: 'Given your balance, amount of time you could go without income'
	String get subtitle => 'Given your balance, amount of time you could go without income';

	/// en: 'You couldn't survive a month without income at this rate of expenses!'
	String get text_zero => 'You couldn\'t survive a month without income at this rate of expenses!';

	/// en: 'You could barely survive approximately a month without income at this rate of expenses!'
	String get text_one => 'You could barely survive approximately a month without income at this rate of expenses!';

	/// en: 'You could survive approximately <b>{{ n }} months</b> without income at this rate of spending.'
	String text_other({required Object n}) => 'You could survive approximately <b>${n} months</b> without income at this rate of spending.';

	/// en: 'You could survive approximately <b>all your life</b> without income at this rate of spending.'
	String get text_infinite => 'You could survive approximately <b>all your life</b> without income at this rate of spending.';

	/// en: 'Remember that it is advisable to always keep this ratio above 5 months at least. If you see that you do not have a sufficient savings cushion, reduce unnecessary expenses.'
	String get suggestion => 'Remember that it is advisable to always keep this ratio above 5 months at least. If you see that you do not have a sufficient savings cushion, reduce unnecessary expenses.';

	/// en: 'It looks like we don't have enough expenses to calculate how many months you could survive without income. Enter a few transactions and come back here to check your financial health'
	String get insufficient_data => 'It looks like we don\'t have enough expenses to calculate how many months you could survive without income. Enter a few transactions and come back here to check your financial health';
}

// Path: financial_health.savings_percentage
class TranslationsFinancialHealthSavingsPercentageEn {
	TranslationsFinancialHealthSavingsPercentageEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Savings percentage'
	String get title => 'Savings percentage';

	/// en: 'What part of your income is not spent in this period'
	String get subtitle => 'What part of your income is not spent in this period';

	late final TranslationsFinancialHealthSavingsPercentageTextEn text = TranslationsFinancialHealthSavingsPercentageTextEn.internal(_root);

	/// en: 'Remember that it is advisable to save at least 15-20% of what you earn.'
	String get suggestion => 'Remember that it is advisable to save at least 15-20% of what you earn.';
}

// Path: icon_selector.scopes
class TranslationsIconSelectorScopesEn {
	TranslationsIconSelectorScopesEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Transport'
	String get transport => 'Transport';

	/// en: 'Money'
	String get money => 'Money';

	/// en: 'Food'
	String get food => 'Food';

	/// en: 'Health'
	String get medical => 'Health';

	/// en: 'Leisure'
	String get entertainment => 'Leisure';

	/// en: 'Technology'
	String get technology => 'Technology';

	/// en: 'Others'
	String get other => 'Others';

	/// en: 'Financial institutions'
	String get logos_financial_institutions => 'Financial institutions';
}

// Path: transaction.next_payments
class TranslationsTransactionNextPaymentsEn {
	TranslationsTransactionNextPaymentsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Accept'
	String get accept => 'Accept';

	/// en: 'Skip'
	String get skip => 'Skip';

	/// en: 'Successfully skipped transaction'
	String get skip_success => 'Successfully skipped transaction';

	/// en: 'Skip transaction'
	String get skip_dialog_title => 'Skip transaction';

	/// en: 'This action is irreversible. We will move the date of the next move to {{date}}'
	String skip_dialog_msg({required Object date}) => 'This action is irreversible. We will move the date of the next move to ${date}';

	/// en: 'Accept today'
	String get accept_today => 'Accept today';

	/// en: 'Accept in required date ({{date}})'
	String accept_in_required_date({required Object date}) => 'Accept in required date (${date})';

	/// en: 'Accept transaction'
	String get accept_dialog_title => 'Accept transaction';

	/// en: 'The new status of the transaction will be null. You can re-edit the status of this transaction whenever you want'
	String get accept_dialog_msg_single => 'The new status of the transaction will be null. You can re-edit the status of this transaction whenever you want';

	/// en: 'This action will create a new transaction with date {{date}}. You will be able to check the details of this transaction on the transaction page'
	String accept_dialog_msg({required Object date}) => 'This action will create a new transaction with date ${date}. You will be able to check the details of this transaction on the transaction page';

	/// en: 'The recurring rule has been completed, there are no more payments to make!'
	String get recurrent_rule_finished => 'The recurring rule has been completed, there are no more payments to make!';
}

// Path: transaction.list
class TranslationsTransactionListEn {
	TranslationsTransactionListEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'All transactions'
	String get all => 'All transactions';

	/// en: 'No transactions found to display here. Add a few transactions in the app and maybe you'll have better luck next time.'
	String get empty => 'No transactions found to display here. Add a few transactions in the app and maybe you\'ll have better luck next time.';

	/// en: 'Search by category, description...'
	String get searcher_placeholder => 'Search by category, description...';

	/// en: 'No transactions found matching the search criteria'
	String get searcher_no_results => 'No transactions found matching the search criteria';

	/// en: 'Loading more transactions...'
	String get loading => 'Loading more transactions...';

	/// en: '(one) {{{n}} selected} (other) {{{n}} selected}'
	String selected_short({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} selected',
		other: '${n} selected',
	);

	/// en: '(one) {{{n}} transaction selected} (other) {{{n}} transactions selected}'
	String selected_long({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} transaction selected',
		other: '${n} transactions selected',
	);

	late final TranslationsTransactionListBulkEditEn bulk_edit = TranslationsTransactionListBulkEditEn.internal(_root);
}

// Path: transaction.filters
class TranslationsTransactionFiltersEn {
	TranslationsTransactionFiltersEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Transaction filters'
	String get title => 'Transaction filters';

	/// en: 'From amount'
	String get from_value => 'From amount';

	/// en: 'Up to amount'
	String get to_value => 'Up to amount';

	/// en: 'From {{ x }}'
	String from_value_def({required Object x}) => 'From ${x}';

	/// en: 'Up to {{ x }}'
	String to_value_def({required Object x}) => 'Up to ${x}';

	/// en: 'From the {{ date }}'
	String from_date_def({required Object date}) => 'From the ${date}';

	/// en: 'Up to the {{ date }}'
	String to_date_def({required Object date}) => 'Up to the ${date}';

	/// en: 'Reset filters'
	String get reset => 'Reset filters';

	late final TranslationsTransactionFiltersSavedEn saved = TranslationsTransactionFiltersSavedEn.internal(_root);
}

// Path: transaction.form
class TranslationsTransactionFormEn {
	TranslationsTransactionFormEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final TranslationsTransactionFormValidatorsEn validators = TranslationsTransactionFormValidatorsEn.internal(_root);

	/// en: 'Transaction title'
	String get title => 'Transaction title';

	/// en: 'Title'
	String get title_short => 'Title';

	/// en: 'Value of the transaction'
	String get value => 'Value of the transaction';

	/// en: 'Tap to see more details'
	String get tap_to_see_more => 'Tap to see more details';

	/// en: '-- No tags --'
	String get no_tags => '-- No tags --';

	/// en: 'Description'
	String get description => 'Description';

	/// en: 'Tap here to enter a more detailed description about this transaction'
	String get description_info => 'Tap here to enter a more detailed description about this transaction';

	/// en: 'Exchnage rate to {{ currency }}'
	String exchange_to_preferred_title({required Object currency}) => 'Exchnage rate to ${currency}';

	/// en: 'On transaction date'
	String get exchange_to_preferred_in_date => 'On transaction date';
}

// Path: transaction.receipt_import
class TranslationsTransactionReceiptImportEn {
	TranslationsTransactionReceiptImportEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'From receipt (gallery)'
	String get entry_gallery => 'From receipt (gallery)';

	/// en: 'From receipt (camera)'
	String get entry_camera => 'From receipt (camera)';

	/// en: 'Processing OCR...'
	String get processing_ocr => 'Processing OCR...';

	/// en: 'Processing AI...'
	String get processing_ai => 'Processing AI...';

	/// en: 'Done'
	String get processing_done => 'Done';

	/// en: 'Review receipt'
	String get review_title => 'Review receipt';

	/// en: 'Validate and edit fields before creating the transaction'
	String get review_subtitle => 'Validate and edit fields before creating the transaction';

	/// en: 'Continue'
	String get review_cta_continue => 'Continue';

	/// en: 'Retry'
	String get review_cta_retry => 'Retry';

	late final TranslationsTransactionReceiptImportErrorEn error = TranslationsTransactionReceiptImportErrorEn.internal(_root);
	late final TranslationsTransactionReceiptImportFieldEn field = TranslationsTransactionReceiptImportFieldEn.internal(_root);
}

// Path: transaction.reversed
class TranslationsTransactionReversedEn {
	TranslationsTransactionReversedEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Inverse transaction'
	String get title => 'Inverse transaction';

	/// en: 'Inverse tr.'
	String get title_short => 'Inverse tr.';

	/// en: 'Despite being an expense transaction, it has a positive amount. These types of transactions can be used to represent the return of a previously recorded expense, such as a refund or having the payment of a debt.'
	String get description_for_expenses => 'Despite being an expense transaction, it has a positive amount. These types of transactions can be used to represent the return of a previously recorded expense, such as a refund or having the payment of a debt.';

	/// en: 'Despite being an income transaction, it has a negative amount. These types of transactions can be used to void or correct an income that was incorrectly recorded, to reflect a return or refund of money or to record payment of debts.'
	String get description_for_incomes => 'Despite being an income transaction, it has a negative amount. These types of transactions can be used to void or correct an income that was incorrectly recorded, to reflect a return or refund of money or to record payment of debts.';
}

// Path: transaction.status
class TranslationsTransactionStatusEn {
	TranslationsTransactionStatusEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: '(one) {Status} (other) {Statuses}'
	String display({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Status',
		other: 'Statuses',
	);

	/// en: 'Transaction status'
	String get display_long => 'Transaction status';

	/// en: '{{ status }} transaction'
	String tr_status({required Object status}) => '${status} transaction';

	/// en: 'Stateless'
	String get none => 'Stateless';

	/// en: 'Transaction without a specific state'
	String get none_descr => 'Transaction without a specific state';

	/// en: 'Reconciled'
	String get reconciled => 'Reconciled';

	/// en: 'This transaction has already been validated and corresponds to a real transaction from your bank'
	String get reconciled_descr => 'This transaction has already been validated and corresponds to a real transaction from your bank';

	/// en: 'Unreconciled'
	String get unreconciled => 'Unreconciled';

	/// en: 'This transaction has not yet been validated and therefore does not yet appear in your real bank accounts. However, it counts for the calculation of balances and statistics in Bolsio'
	String get unreconciled_descr => 'This transaction has not yet been validated and therefore does not yet appear in your real bank accounts. However, it counts for the calculation of balances and statistics in Bolsio';

	/// en: 'Pending'
	String get pending => 'Pending';

	/// en: 'This transaction is pending and therefore it will not be taken into account when calculating balances and statistics'
	String get pending_descr => 'This transaction is pending and therefore it will not be taken into account when calculating balances and statistics';

	/// en: 'Voided'
	String get voided => 'Voided';

	/// en: 'Void/cancelled transaction due to payment error or any other reason. It will not be taken into account when calculating balances and statistics'
	String get voided_descr => 'Void/cancelled transaction due to payment error or any other reason. It will not be taken into account when calculating balances and statistics';
}

// Path: transaction.types
class TranslationsTransactionTypesEn {
	TranslationsTransactionTypesEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: '(one) {Transaction type} (other) {Transaction types}'
	String display({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Transaction type',
		other: 'Transaction types',
	);

	/// en: '(one) {Income} (other) {Incomes}'
	String income({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Income',
		other: 'Incomes',
	);

	/// en: '(one) {Expense} (other) {Expenses}'
	String expense({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Expense',
		other: 'Expenses',
	);

	/// en: '(one) {Transfer} (other) {Transfers}'
	String transfer({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Transfer',
		other: 'Transfers',
	);
}

// Path: transfer.form
class TranslationsTransferFormEn {
	TranslationsTransferFormEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Origin account'
	String get from => 'Origin account';

	/// en: 'Destination account'
	String get to => 'Destination account';

	late final TranslationsTransferFormValueInDestinyEn value_in_destiny = TranslationsTransferFormValueInDestinyEn.internal(_root);
}

// Path: recurrent_transactions.details
class TranslationsRecurrentTransactionsDetailsEn {
	TranslationsRecurrentTransactionsDetailsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Recurrent transaction'
	String get title => 'Recurrent transaction';

	/// en: 'The next moves for this transaction are shown below. You can accept the first move or skip this move'
	String get descr => 'The next moves for this transaction are shown below. You can accept the first move or skip this move';

	/// en: 'This movement is the last of the recurring rule, so this rule will be automatically deleted when confirming this action'
	String get last_payment_info => 'This movement is the last of the recurring rule, so this rule will be automatically deleted when confirming this action';

	/// en: 'Delete recurring transaction'
	String get delete_header => 'Delete recurring transaction';

	/// en: 'This action is irreversible and will not affect transactions you have already confirmed/paid for'
	String get delete_message => 'This action is irreversible and will not affect transactions you have already confirmed/paid for';
}

// Path: recurrent_transactions.status
class TranslationsRecurrentTransactionsStatusEn {
	TranslationsRecurrentTransactionsStatusEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Delayed by {{x}}d'
	String delayed_by({required Object x}) => 'Delayed by ${x}d';

	/// en: 'In {{x}} days'
	String coming_in({required Object x}) => 'In ${x} days';
}

// Path: account.types
class TranslationsAccountTypesEn {
	TranslationsAccountTypesEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Account type'
	String get title => 'Account type';

	/// en: 'Once the type of account has been chosen, it cannot be changed in the future'
	String get warning => 'Once the type of account has been chosen, it cannot be changed in the future';

	/// en: 'Normal account'
	String get normal => 'Normal account';

	/// en: 'Useful to record your day-to-day finances. It is the most common account, it allows you to add expenses, income...'
	String get normal_descr => 'Useful to record your day-to-day finances. It is the most common account, it allows you to add expenses, income...';

	/// en: 'Savings account'
	String get saving => 'Savings account';

	/// en: 'You will only be able to add and withdraw money from it from other accounts. Perfect to start saving money'
	String get saving_descr => 'You will only be able to add and withdraw money from it from other accounts. Perfect to start saving money';
}

// Path: account.form
class TranslationsAccountFormEn {
	TranslationsAccountFormEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Account name'
	String get name => 'Account name';

	/// en: 'Ex: Savings account'
	String get name_placeholder => 'Ex: Savings account';

	/// en: 'Notes'
	String get notes => 'Notes';

	/// en: 'Type some notes/description about this account'
	String get notes_placeholder => 'Type some notes/description about this account';

	/// en: 'Initial balance'
	String get initial_balance => 'Initial balance';

	/// en: 'Current balance'
	String get current_balance => 'Current balance';

	/// en: 'Create account'
	String get create => 'Create account';

	/// en: 'Edit account'
	String get edit => 'Edit account';

	/// en: 'You do not have information on exchange rates for this currency. 1.0 will be used as the default exchange rate. You can modify this in the settings'
	String get currency_not_found_warn => 'You do not have information on exchange rates for this currency. 1.0 will be used as the default exchange rate. You can modify this in the settings';

	/// en: 'There is already another one with the same name, please write another'
	String get already_exists => 'There is already another one with the same name, please write another';

	/// en: 'There are transactions in this account with a date before the opening date'
	String get tr_before_opening_date => 'There are transactions in this account with a date before the opening date';

	/// en: 'IBAN'
	String get iban => 'IBAN';

	/// en: 'SWIFT'
	String get swift => 'SWIFT';

	/// en: 'Track since'
	String get tracked_since => 'Track since';

	/// en: 'Optional'
	String get tracked_since_hint => 'Optional';

	/// en: 'Transactions before this date will appear in history but will not affect balance.'
	String get tracked_since_info => 'Transactions before this date will appear in history but will not affect balance.';

	/// en: 'Track-since date cannot be later than the account closing date.'
	String get tracked_since_validation_after_closing => 'Track-since date cannot be later than the account closing date.';
}

// Path: account.badge
class TranslationsAccountBadgeEn {
	TranslationsAccountBadgeEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Historical'
	String get pre_tracking => 'Historical';

	/// en: 'Does not affect current balance'
	String get pre_tracking_tooltip => 'Does not affect current balance';
}

// Path: account.retroactive
class TranslationsAccountRetroactiveEn {
	TranslationsAccountRetroactiveEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Balance impact'
	String get preview_title => 'Balance impact';

	/// en: 'Current balance: {{current}} → New balance: {{simulated}}'
	String preview_message({required Object current, required Object simulated}) => 'Current balance: ${current} → New balance: ${simulated}';

	/// en: 'Type CONFIRM to proceed'
	String get strong_confirm_hint => 'Type CONFIRM to proceed';

	/// en: 'Text does not match. Change canceled.'
	String get strong_confirm_mismatch => 'Text does not match. Change canceled.';

	/// en: 'Accept'
	String get accept => 'Accept';

	/// en: 'Cancel'
	String get cancel => 'Cancel';
}

// Path: account.delete
class TranslationsAccountDeleteEn {
	TranslationsAccountDeleteEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Delete account?'
	String get warning_header => 'Delete account?';

	/// en: 'This action will delete this account and all its transactions'
	String get warning_text => 'This action will delete this account and all its transactions';

	/// en: 'Account deleted successfully'
	String get success => 'Account deleted successfully';
}

// Path: account.close
class TranslationsAccountCloseEn {
	TranslationsAccountCloseEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Close account'
	String get title => 'Close account';

	/// en: 'Close'
	String get title_short => 'Close';

	/// en: 'This account will no longer appear in certain listings and you will not be able to create transactions in it with a date later than the one specified below. This action does not affect any transactions or balance, and you can also reopen this account at any time. '
	String get warn => 'This account will no longer appear in certain listings and you will not be able to create transactions in it with a date later than the one specified below. This action does not affect any transactions or balance, and you can also reopen this account at any time. ';

	/// en: 'You must have a current balance of 0 in this account to close it. Please edit the account before continuing'
	String get should_have_zero_balance => 'You must have a current balance of 0 in this account to close it. Please edit the account before continuing';

	/// en: 'This account has transactions after the specified close date. Delete them or edit the account close date before continuing'
	String get should_have_no_transactions => 'This account has transactions after the specified close date. Delete them or edit the account close date before continuing';

	/// en: 'Account closed successfully'
	String get success => 'Account closed successfully';

	/// en: 'Account successfully re-opened'
	String get unarchive_succes => 'Account successfully re-opened';
}

// Path: account.select
class TranslationsAccountSelectEn {
	TranslationsAccountSelectEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Select an account'
	String get one => 'Select an account';

	/// en: 'All accounts'
	String get all => 'All accounts';

	/// en: 'Select accounts'
	String get multiple => 'Select accounts';
}

// Path: currencies.exchange_rate_form
class TranslationsCurrenciesExchangeRateFormEn {
	TranslationsCurrenciesExchangeRateFormEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'The currency cannot be equal to the user currency'
	String get equal_to_preferred_warn => 'The currency cannot be equal to the user currency';

	/// en: 'An exchange rate for this currency in this date already exists. If you continue, the previous one will be overwritten'
	String get override_existing_warn => 'An exchange rate for this currency in this date already exists. If you continue, the previous one will be overwritten';

	/// en: 'Please specify a currency'
	String get specify_a_currency => 'Please specify a currency';

	/// en: 'Add exchange rate'
	String get add => 'Add exchange rate';

	/// en: 'Exchange rate added successfully'
	String get add_success => 'Exchange rate added successfully';

	/// en: 'Edit exchange rate'
	String get edit => 'Edit exchange rate';

	/// en: 'Exchange rate edited successfully'
	String get edit_success => 'Exchange rate edited successfully';

	/// en: 'Delete all exchange rates'
	String get remove_all => 'Delete all exchange rates';

	/// en: 'This action is irreversible and will delete all exchange rates for this currency'
	String get remove_all_warning => 'This action is irreversible and will delete all exchange rates for this currency';
}

// Path: currencies.types
class TranslationsCurrenciesTypesEn {
	TranslationsCurrenciesTypesEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Currency type'
	String get display => 'Currency type';

	/// en: 'FIAT'
	String get fiat => 'FIAT';

	/// en: 'Cryptocurrency'
	String get crypto => 'Cryptocurrency';

	/// en: 'Other'
	String get other => 'Other';
}

// Path: currencies.currency_form
class TranslationsCurrenciesCurrencyFormEn {
	TranslationsCurrenciesCurrencyFormEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Display Name'
	String get name => 'Display Name';

	/// en: 'Currency Code'
	String get code => 'Currency Code';

	/// en: 'Symbol'
	String get symbol => 'Symbol';

	/// en: 'Decimal Digits'
	String get decimal_digits => 'Decimal Digits';

	/// en: 'Create currency'
	String get create => 'Create currency';

	/// en: 'Currency created successfully'
	String get create_success => 'Currency created successfully';

	/// en: 'Edit currency'
	String get edit => 'Edit currency';

	/// en: 'Currency edited successfully'
	String get edit_success => 'Currency edited successfully';

	/// en: 'Delete currency'
	String get delete => 'Delete currency';

	/// en: 'Currency deleted successfully'
	String get delete_success => 'Currency deleted successfully';

	/// en: 'A currency with this code already exists. You may want to edit it'
	String get already_exists => 'A currency with this code already exists. You may want to edit it';
}

// Path: tags.form
class TranslationsTagsFormEn {
	TranslationsTagsFormEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Tag name'
	String get name => 'Tag name';

	/// en: 'Description'
	String get description => 'Description';
}

// Path: tags.select
class TranslationsTagsSelectEn {
	TranslationsTagsSelectEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Select tags'
	String get title => 'Select tags';

	/// en: 'All the tags'
	String get all => 'All the tags';
}

// Path: categories.select
class TranslationsCategoriesSelectEn {
	TranslationsCategoriesSelectEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Select categories'
	String get title => 'Select categories';

	/// en: 'Select a category'
	String get select_one => 'Select a category';

	/// en: 'Choose a subcategory'
	String get select_subcategory => 'Choose a subcategory';

	/// en: 'Without subcategory'
	String get without_subcategory => 'Without subcategory';

	/// en: 'All categories'
	String get all => 'All categories';

	/// en: 'All'
	String get all_short => 'All';
}

// Path: budgets.form
class TranslationsBudgetsFormEn {
	TranslationsBudgetsFormEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Add a budget'
	String get title => 'Add a budget';

	/// en: 'Budget name'
	String get name => 'Budget name';

	/// en: 'Limit quantity'
	String get value => 'Limit quantity';

	/// en: 'Add budget'
	String get create => 'Add budget';

	/// en: 'Budget created successfully'
	String get create_success => 'Budget created successfully';

	/// en: 'Edit budget'
	String get edit => 'Edit budget';

	/// en: 'Budget edited successfully'
	String get edit_success => 'Budget edited successfully';

	/// en: 'The budgets can not have a negative amount'
	String get negative_warn => 'The budgets can not have a negative amount';
}

// Path: budgets.details
class TranslationsBudgetsDetailsEn {
	TranslationsBudgetsDetailsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Budget Details'
	String get title => 'Budget Details';

	/// en: 'Statistics'
	String get statistics => 'Statistics';

	/// en: 'Budgeted'
	String get budget_value => 'Budgeted';

	/// en: 'Expenditure evolution'
	String get expend_evolution => 'Expenditure evolution';

	/// en: 'It seems that you have not made any expenses related to this budget'
	String get no_transactions => 'It seems that you have not made any expenses related to this budget';
}

// Path: budgets.target_timeline_statuses
class TranslationsBudgetsTargetTimelineStatusesEn {
	TranslationsBudgetsTargetTimelineStatusesEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Active budget'
	String get active => 'Active budget';

	/// en: 'Finished budget'
	String get past => 'Finished budget';

	/// en: 'Future budget'
	String get future => 'Future budget';
}

// Path: budgets.progress
class TranslationsBudgetsProgressEn {
	TranslationsBudgetsProgressEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final TranslationsBudgetsProgressLabelsEn labels = TranslationsBudgetsProgressLabelsEn.internal(_root);
	late final TranslationsBudgetsProgressDescriptionEn description = TranslationsBudgetsProgressDescriptionEn.internal(_root);
}

// Path: goals.type
class TranslationsGoalsTypeEn {
	TranslationsGoalsTypeEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Goal Type'
	String get display => 'Goal Type';

	late final TranslationsGoalsTypeIncomeEn income = TranslationsGoalsTypeIncomeEn.internal(_root);
	late final TranslationsGoalsTypeExpenseEn expense = TranslationsGoalsTypeExpenseEn.internal(_root);
}

// Path: goals.form
class TranslationsGoalsFormEn {
	TranslationsGoalsFormEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'New Goal'
	String get new_title => 'New Goal';

	/// en: 'Edit Goal'
	String get edit_title => 'Edit Goal';

	/// en: 'Target Amount'
	String get target_amount => 'Target Amount';

	/// en: 'Initial Amount'
	String get initial_amount => 'Initial Amount';

	/// en: 'Name'
	String get name => 'Name';

	/// en: 'My Saving Goal'
	String get name_hint => 'My Saving Goal';

	/// en: 'Goal created successfully'
	String get create_success => 'Goal created successfully';

	/// en: 'Goal edited successfully'
	String get edit_success => 'Goal edited successfully';

	/// en: 'The goal amount cannot be negative'
	String get negative_warn => 'The goal amount cannot be negative';
}

// Path: goals.details
class TranslationsGoalsDetailsEn {
	TranslationsGoalsDetailsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Goal Details'
	String get title => 'Goal Details';

	/// en: 'Statistics'
	String get statistics => 'Statistics';

	/// en: 'Goal Target'
	String get goal_value => 'Goal Target';

	/// en: 'Evolution'
	String get evolution => 'Evolution';

	/// en: 'It seems that you have not made any transactions related to this goal'
	String get no_transactions => 'It seems that you have not made any transactions related to this goal';
}

// Path: goals.target_timeline_statuses
class TranslationsGoalsTargetTimelineStatusesEn {
	TranslationsGoalsTargetTimelineStatusesEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Active goal'
	String get active => 'Active goal';

	/// en: 'Finished goal'
	String get past => 'Finished goal';

	/// en: 'Future goal'
	String get future => 'Future goal';
}

// Path: goals.progress
class TranslationsGoalsProgressEn {
	TranslationsGoalsProgressEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final TranslationsGoalsProgressLabelsEn labels = TranslationsGoalsProgressLabelsEn.internal(_root);
	late final TranslationsGoalsProgressDescriptionEn description = TranslationsGoalsProgressDescriptionEn.internal(_root);
}

// Path: debts.form
class TranslationsDebtsFormEn {
	TranslationsDebtsFormEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Debt name'
	String get name => 'Debt name';

	/// en: 'Initial amount'
	String get initial_amount => 'Initial amount';

	/// en: 'Total amount'
	String get total_amount => 'Total amount';

	/// en: 'Initial value'
	String get step_initial_value => 'Initial value';

	/// en: 'Details'
	String get step_details => 'Details';

	late final TranslationsDebtsFormFromTransactionEn from_transaction = TranslationsDebtsFormFromTransactionEn.internal(_root);
	late final TranslationsDebtsFormFromAmountEn from_amount = TranslationsDebtsFormFromAmountEn.internal(_root);
}

// Path: debts.direction
class TranslationsDebtsDirectionEn {
	TranslationsDebtsDirectionEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Lent'
	String get lent => 'Lent';

	/// en: 'Borrowed'
	String get borrowed => 'Borrowed';
}

// Path: debts.status
class TranslationsDebtsStatusEn {
	TranslationsDebtsStatusEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Active'
	String get active => 'Active';

	/// en: 'Closed'
	String get close => 'Closed';
}

// Path: debts.details
class TranslationsDebtsDetailsEn {
	TranslationsDebtsDetailsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Collected amount'
	String get collected_amount => 'Collected amount';

	/// en: 'Remaining'
	String get remaining => 'Remaining';

	/// en: 'No deadline'
	String get no_deadline => 'No deadline';

	/// en: 'In {{x}} days'
	String in_days({required Object x}) => 'In ${x} days';

	/// en: 'Due today'
	String get due_today => 'Due today';

	/// en: '{{x}} days ago'
	String days_ago({required Object x}) => '${x} days ago';

	/// en: 'Overdue by {{x}} days'
	String overdue_by({required Object x}) => 'Overdue by ${x} days';

	/// en: '/ day'
	String get per_day => '/ day';

	/// en: 'No transactions found for this debt'
	String get no_transactions => 'No transactions found for this debt';
}

// Path: debts.empty
class TranslationsDebtsEmptyEn {
	TranslationsDebtsEmptyEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'No active debts found. Start by creating a new debt by clicking the button below'
	String get no_debts_active => 'No active debts found. Start by creating a new debt by clicking the button below';

	/// en: 'No closed debts found. A debt is closed when you have collected all the money from it or you have paid all the money you owed.'
	String get no_debts_closed => 'No closed debts found. A debt is closed when you have collected all the money from it or you have paid all the money you owed.';
}

// Path: debts.actions
class TranslationsDebtsActionsEn {
	TranslationsDebtsActionsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final TranslationsDebtsActionsEditEn edit = TranslationsDebtsActionsEditEn.internal(_root);
	late final TranslationsDebtsActionsDeleteEn delete = TranslationsDebtsActionsDeleteEn.internal(_root);
	late final TranslationsDebtsActionsAddRegisterEn add_register = TranslationsDebtsActionsAddRegisterEn.internal(_root);
	late final TranslationsDebtsActionsLinkTransactionEn link_transaction = TranslationsDebtsActionsLinkTransactionEn.internal(_root);
	late final TranslationsDebtsActionsUnlinkTransactionEn unlink_transaction = TranslationsDebtsActionsUnlinkTransactionEn.internal(_root);
	late final TranslationsDebtsActionsNewTransactionEn new_transaction = TranslationsDebtsActionsNewTransactionEn.internal(_root);
	late final TranslationsDebtsActionsCreateEn create = TranslationsDebtsActionsCreateEn.internal(_root);
}

// Path: backup.export
class TranslationsBackupExportEn {
	TranslationsBackupExportEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Export your data'
	String get title => 'Export your data';

	/// en: 'Export'
	String get title_short => 'Export';

	/// en: 'Type of export'
	String get type_of_export => 'Type of export';

	/// en: 'Options'
	String get other_options => 'Options';

	/// en: 'Full backup'
	String get all => 'Full backup';

	/// en: 'Export all your data (accounts, transactions, budgets, settings...). Import them again at any time so you don't lose anything.'
	String get all_descr => 'Export all your data (accounts, transactions, budgets, settings...). Import them again at any time so you don\'t lose anything.';

	/// en: 'Transactions backup'
	String get transactions => 'Transactions backup';

	/// en: 'Export your transactions in CSV so you can more easily analyze them in other programs or applications.'
	String get transactions_descr => 'Export your transactions in CSV so you can more easily analyze them in other programs or applications.';

	/// en: '(one) {1 transaction to export} (other) {{{ n }} transactions to export}'
	String transactions_to_export({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '1 transaction to export',
		other: '${n} transactions to export',
	);

	/// en: 'Download your data in different formats'
	String get description => 'Download your data in different formats';

	/// en: 'Send file'
	String get send_file => 'Send file';

	/// en: 'See folder'
	String get see_folder => 'See folder';

	/// en: 'File saved successfully in {{x}}'
	String success({required Object x}) => 'File saved successfully in ${x}';

	/// en: 'Error downloading the file. Please contact the developer via lozin.technologies@gmail.com'
	String get error => 'Error downloading the file. Please contact the developer via lozin.technologies@gmail.com';

	/// en: 'Save/Send file'
	String get dialog_title => 'Save/Send file';
}

// Path: backup.import
class TranslationsBackupImportEn {
	TranslationsBackupImportEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Import your data'
	String get title => 'Import your data';

	/// en: 'Import'
	String get title_short => 'Import';

	/// en: 'Restore Backup'
	String get restore_backup => 'Restore Backup';

	/// en: 'Import a previously saved database from Bolsio. This action will replace any current application data with the new data'
	String get restore_backup_descr => 'Import a previously saved database from Bolsio. This action will replace any current application data with the new data';

	/// en: 'When importing a new database, you will lose all data currently saved in the app. It is recommended to make a backup before continuing. Do not upload here any file whose origin you do not know, upload only files that you have previously downloaded from Bolsio'
	String get restore_backup_warn_description => 'When importing a new database, you will lose all data currently saved in the app. It is recommended to make a backup before continuing. Do not upload here any file whose origin you do not know, upload only files that you have previously downloaded from Bolsio';

	/// en: 'Overwrite all data'
	String get restore_backup_warn_title => 'Overwrite all data';

	/// en: 'Select other file'
	String get select_other_file => 'Select other file';

	/// en: 'Tap to select a file'
	String get tap_to_select_file => 'Tap to select a file';

	late final TranslationsBackupImportManualImportEn manual_import = TranslationsBackupImportManualImportEn.internal(_root);

	/// en: 'Import performed successfully'
	String get success => 'Import performed successfully';

	/// en: 'Error importing file. Please contact developer via lozin.technologies@gmail.com'
	String get error => 'Error importing file. Please contact developer via lozin.technologies@gmail.com';

	/// en: 'Import was cancelled by the user'
	String get cancelled => 'Import was cancelled by the user';
}

// Path: backup.about
class TranslationsBackupAboutEn {
	TranslationsBackupAboutEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Information about your database'
	String get title => 'Information about your database';

	/// en: 'Creation date'
	String get create_date => 'Creation date';

	/// en: 'Last modified'
	String get modify_date => 'Last modified';

	/// en: 'Last backup'
	String get last_backup => 'Last backup';

	/// en: 'Size'
	String get size => 'Size';
}

// Path: settings.general
class TranslationsSettingsGeneralEn {
	TranslationsSettingsGeneralEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'General Settings'
	String get menu_title => 'General Settings';

	/// en: 'Language, privacy, and more'
	String get menu_descr => 'Language, privacy, and more';

	/// en: 'Show all decimal places'
	String get show_all_decimals => 'Show all decimal places';

	/// en: 'Whether to show all decimals places even if there are trailing zeros'
	String get show_all_decimals_descr => 'Whether to show all decimals places even if there are trailing zeros';

	late final TranslationsSettingsGeneralLanguageEn language = TranslationsSettingsGeneralLanguageEn.internal(_root);
	late final TranslationsSettingsGeneralLocaleEn locale = TranslationsSettingsGeneralLocaleEn.internal(_root);
}

// Path: settings.security
class TranslationsSettingsSecurityEn {
	TranslationsSettingsSecurityEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Security'
	String get title => 'Security';

	/// en: 'Private mode at launch'
	String get private_mode_at_launch => 'Private mode at launch';

	/// en: 'Launch the app in private mode by default'
	String get private_mode_at_launch_descr => 'Launch the app in private mode by default';

	/// en: 'Private mode'
	String get private_mode => 'Private mode';

	/// en: 'Hide all monetary values'
	String get private_mode_descr => 'Hide all monetary values';

	/// en: 'Private mode activated'
	String get private_mode_activated => 'Private mode activated';

	/// en: 'Private mode disabled'
	String get private_mode_deactivated => 'Private mode disabled';

	late final TranslationsSettingsSecurityBiometricEn biometric = TranslationsSettingsSecurityBiometricEn.internal(_root);
}

// Path: settings.hidden_mode
class TranslationsSettingsHiddenModeEn {
	TranslationsSettingsHiddenModeEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Hidden Mode'
	String get title => 'Hidden Mode';

	/// en: 'Hide your savings accounts behind a PIN'
	String get menu_descr => 'Hide your savings accounts behind a PIN';

	/// en: 'Enable Hidden Mode'
	String get enable => 'Enable Hidden Mode';

	/// en: 'When active, your savings accounts and their transactions are hidden from balances, charts and lists. To see the real balance: 6 taps on your profile picture + PIN.'
	String get description => 'When active, your savings accounts and their transactions are hidden from balances, charts and lists. To see the real balance: 6 taps on your profile picture + PIN.';

	/// en: 'Change PIN'
	String get change_pin => 'Change PIN';

	/// en: 'Replace your current PIN with a new one'
	String get change_pin_descr => 'Replace your current PIN with a new one';

	/// en: 'Active'
	String get enabled_badge => 'Active';

	late final TranslationsSettingsHiddenModePinEn pin = TranslationsSettingsHiddenModePinEn.internal(_root);
}

// Path: settings.transactions
class TranslationsSettingsTransactionsEn {
	TranslationsSettingsTransactionsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Transactions'
	String get menu_title => 'Transactions';

	/// en: 'Configure the behavior of your transactions'
	String get menu_descr => 'Configure the behavior of your transactions';

	/// en: 'Transactions Settings'
	String get title => 'Transactions Settings';

	late final TranslationsSettingsTransactionsStyleEn style = TranslationsSettingsTransactionsStyleEn.internal(_root);
	late final TranslationsSettingsTransactionsSwipeActionsEn swipe_actions = TranslationsSettingsTransactionsSwipeActionsEn.internal(_root);
	late final TranslationsSettingsTransactionsDefaultValuesEn default_values = TranslationsSettingsTransactionsDefaultValuesEn.internal(_root);
	late final TranslationsSettingsTransactionsDefaultTypeEn default_type = TranslationsSettingsTransactionsDefaultTypeEn.internal(_root);
}

// Path: settings.auto_import
class TranslationsSettingsAutoImportEn {
	TranslationsSettingsAutoImportEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Bank auto-import'
	String get menu_title => 'Bank auto-import';
}

// Path: settings.appearance
class TranslationsSettingsAppearanceEn {
	TranslationsSettingsAppearanceEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Theme & Style'
	String get menu_title => 'Theme & Style';

	/// en: 'Theme selection, colors and other things related to the app appearance'
	String get menu_descr => 'Theme selection, colors and other things related to the app appearance';

	/// en: 'Theme and colors'
	String get theme_and_colors => 'Theme and colors';

	late final TranslationsSettingsAppearanceThemeEn theme = TranslationsSettingsAppearanceThemeEn.internal(_root);

	/// en: 'AMOLED mode'
	String get amoled_mode => 'AMOLED mode';

	/// en: 'Use a pure black wallpaper when possible. This will slightly help the battery of devices with AMOLED screens'
	String get amoled_mode_descr => 'Use a pure black wallpaper when possible. This will slightly help the battery of devices with AMOLED screens';

	/// en: 'Dynamic colors'
	String get dynamic_colors => 'Dynamic colors';

	/// en: 'Use your system accent color whenever possible'
	String get dynamic_colors_descr => 'Use your system accent color whenever possible';

	/// en: 'Accent color'
	String get accent_color => 'Accent color';

	/// en: 'Choose the color the app will use to emphasize certain parts of the interface'
	String get accent_color_descr => 'Choose the color the app will use to emphasize certain parts of the interface';

	/// en: 'Text'
	String get text => 'Text';

	/// en: 'Font'
	String get font => 'Font';

	/// en: 'Platform'
	String get font_platform => 'Platform';
}

// Path: statement_import.capture
class TranslationsStatementImportCaptureEn {
	TranslationsStatementImportCaptureEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Take a photo'
	String get cta_camera => 'Take a photo';

	/// en: 'Upload PDF or image'
	String get cta_file => 'Upload PDF or image';

	/// en: 'Multi-page PDF'
	String get pdf_warning_title => 'Multi-page PDF';

	/// en: 'This PDF has {{pages}} pages. We will only process page 1.'
	String pdf_warning_body({required Object pages}) => 'This PDF has ${pages} pages. We will only process page 1.';

	/// en: 'Continue'
	String get pdf_warning_continue => 'Continue';

	/// en: 'When did you take the capture?'
	String get date_picker_title => 'When did you take the capture?';

	/// en: 'Could not read the image'
	String get error_read => 'Could not read the image';
}

// Path: statement_import.processing
class TranslationsStatementImportProcessingEn {
	TranslationsStatementImportProcessingEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Reading account statement…'
	String get title => 'Reading account statement…';

	/// en: 'Analyzing…'
	String get analyzing => 'Analyzing…';

	/// en: '{{n}} found'
	String found({required Object n}) => '${n} found';

	/// en: 'Cancel'
	String get cancel => 'Cancel';

	/// en: 'Could not read in time. Try again'
	String get error_timeout => 'Could not read in time. Try again';

	/// en: 'Could not read. Try again'
	String get error_generic => 'Could not read. Try again';

	/// en: 'Retry'
	String get retry => 'Retry';

	/// en: 'Back'
	String get back => 'Back';
}

// Path: statement_import.review
class TranslationsStatementImportReviewEn {
	TranslationsStatementImportReviewEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Review movements'
	String get title => 'Review movements';

	/// en: 'No movements detected'
	String get empty => 'No movements detected';

	/// en: 'All'
	String get toggle_all => 'All';

	/// en: 'None'
	String get toggle_none => 'None';

	/// en: 'Continue · {{n}} movements'
	String continue_cta({required Object n}) => 'Continue · ${n} movements';

	/// en: 'AND · only rows meeting {{n}} criteria'
	String and_label({required Object n}) => 'AND · only rows meeting ${n} criteria';

	/// en: 'Clear'
	String get clear => 'Clear';

	/// en: 'Some rows have a date after Fresh Start. They will be included in the history but will not affect the balance.'
	String get informative_warning => 'Some rows have a date after Fresh Start. They will be included in the history but will not affect the balance.';

	/// en: 'Configure Fresh Start first'
	String get fresh_start_dialog_title => 'Configure Fresh Start first';

	/// en: 'To import informative movements (history) you need to configure the date from which you track this account.'
	String get fresh_start_dialog_body => 'To import informative movements (history) you need to configure the date from which you track this account.';

	/// en: 'Configure now'
	String get fresh_start_configure => 'Configure now';

	/// en: 'Already exists'
	String get tag_exists => 'Already exists';

	/// en: 'Fee'
	String get tag_fee => 'Fee';

	/// en: 'Pre-Fresh'
	String get tag_prefresh => 'Pre-Fresh';
}

// Path: statement_import.modes
class TranslationsStatementImportModesEn {
	TranslationsStatementImportModesEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Missing'
	String get missing => 'Missing';

	/// en: 'Income'
	String get income => 'Income';

	/// en: 'Expenses'
	String get expense => 'Expenses';

	/// en: 'Fees'
	String get fees => 'Fees';

	/// en: 'Informative'
	String get informative => 'Informative';
}

// Path: statement_import.confirm
class TranslationsStatementImportConfirmEn {
	TranslationsStatementImportConfirmEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Confirm import'
	String get title => 'Confirm import';

	/// en: '{{n}} movements'
	String movements({required Object n}) => '${n} movements';

	/// en: 'History · does not affect balance'
	String get informative_chip => 'History · does not affect balance';

	/// en: 'Breakdown'
	String get breakdown_title => 'Breakdown';

	/// en: 'Income'
	String get breakdown_income => 'Income';

	/// en: 'Expenses'
	String get breakdown_expense => 'Expenses';

	/// en: 'Fees'
	String get breakdown_fees => 'Fees';

	/// en: 'Net total'
	String get breakdown_total => 'Net total';

	/// en: 'If something is imported incorrectly you can undo from the account history in the next 7 days.'
	String get undo_hint => 'If something is imported incorrectly you can undo from the account history in the next 7 days.';

	/// en: 'Back'
	String get back => 'Back';

	/// en: 'Import'
	String get import_cta => 'Import';

	/// en: 'Could not save. Try again.'
	String get error => 'Could not save. Try again.';
}

// Path: statement_import.success
class TranslationsStatementImportSuccessEn {
	TranslationsStatementImportSuccessEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: '{{n}} movements imported'
	String title({required Object n}) => '${n} movements imported';

	/// en: 'View in history'
	String get view_history => 'View in history';

	/// en: 'Done'
	String get done => 'Done';
}

// Path: statement_import.undo
class TranslationsStatementImportUndoEn {
	TranslationsStatementImportUndoEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Recent import'
	String get banner_title => 'Recent import';

	/// en: '{{n}} movements · {{date}}'
	String banner_body({required Object n, required Object date}) => '${n} movements · ${date}';

	/// en: 'Undo'
	String get undo_cta => 'Undo';

	/// en: 'Undo import?'
	String get dialog_title => 'Undo import?';

	/// en: '{{n}} imported movements will be deleted.'
	String dialog_body({required Object n}) => '${n} imported movements will be deleted.';

	/// en: 'Undo'
	String get dialog_confirm => 'Undo';

	/// en: 'Cancel'
	String get dialog_cancel => 'Cancel';

	/// en: 'Import undone'
	String get success => 'Import undone';
}

// Path: more.search
class TranslationsMoreSearchEn {
	TranslationsMoreSearchEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Search settings…'
	String get hint => 'Search settings…';
}

// Path: more.sections
class TranslationsMoreSectionsEn {
	TranslationsMoreSectionsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Quick access'
	String get quick_access => 'Quick access';

	/// en: 'Management'
	String get management => 'Management';

	/// en: 'Configuration'
	String get configuration => 'Configuration';

	/// en: 'Data'
	String get data => 'Data';

	/// en: 'Tools'
	String get tools => 'Tools';

	/// en: 'About'
	String get about => 'About';
}

// Path: more.account
class TranslationsMoreAccountEn {
	TranslationsMoreAccountEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Sign out'
	String get sign_out => 'Sign out';

	/// en: 'Synced'
	String get sync_active => 'Synced';

	/// en: 'Sync disabled'
	String get sync_inactive => 'Sync disabled';

	/// en: 'No account linked'
	String get no_account => 'No account linked';

	/// en: 'Your account'
	String get fallback_name => 'Your account';

	/// en: 'Firebase Sync'
	String get firebase_sync => 'Firebase Sync';
}

// Path: more.theme
class TranslationsMoreThemeEn {
	TranslationsMoreThemeEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Theme'
	String get title => 'Theme';

	/// en: 'System'
	String get system => 'System';

	/// en: 'Light'
	String get light => 'Light';

	/// en: 'Dark'
	String get dark => 'Dark';

	/// en: 'AMOLED mode'
	String get amoled => 'AMOLED mode';

	/// en: 'More appearance options'
	String get more_options => 'More appearance options';
}

// Path: more.ai
class TranslationsMoreAiEn {
	TranslationsMoreAiEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Bolsi'
	String get title => 'Bolsi';

	/// en: 'Set up your financial assistant'
	String get configure => 'Set up your financial assistant';

	/// en: 'Active · {provider}'
	String get active_with => 'Active · {provider}';
}

// Path: more.data
class TranslationsMoreDataEn {
	TranslationsMoreDataEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Data'
	String get display => 'Data';

	/// en: 'Export and import your data so you don't lose anything'
	String get display_descr => 'Export and import your data so you don\'t lose anything';

	/// en: 'Delete my data'
	String get delete_all => 'Delete my data';

	/// en: 'Stop right there padawan ⚠️⚠️'
	String get delete_all_header1 => 'Stop right there padawan ⚠️⚠️';

	/// en: 'Are you sure you want to continue? All your data will be permanently deleted and cannot be recovered'
	String get delete_all_message1 => 'Are you sure you want to continue? All your data will be permanently deleted and cannot be recovered';

	/// en: 'One last step ⚠️⚠️'
	String get delete_all_header2 => 'One last step ⚠️⚠️';

	/// en: 'By deleting an account you will delete all your stored personal data. Your accounts, transactions, budgets and categories will be deleted and cannot be recovered. Do you agree?'
	String get delete_all_message2 => 'By deleting an account you will delete all your stored personal data. Your accounts, transactions, budgets and categories will be deleted and cannot be recovered. Do you agree?';
}

// Path: more.about_us
class TranslationsMoreAboutUsEn {
	TranslationsMoreAboutUsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'App information'
	String get display => 'App information';

	/// en: 'Find Bolsio’s terms, important info, and connect by reporting bugs or sharing ideas'
	String get description => 'Find Bolsio’s terms, important info, and connect by reporting bugs or sharing ideas';

	late final TranslationsMoreAboutUsLegalEn legal = TranslationsMoreAboutUsLegalEn.internal(_root);
	late final TranslationsMoreAboutUsProjectEn project = TranslationsMoreAboutUsProjectEn.internal(_root);
}

// Path: more.help_us
class TranslationsMoreHelpUsEn {
	TranslationsMoreHelpUsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Help us'
	String get display => 'Help us';

	/// en: 'Find out how you can help Bolsio become better and better'
	String get description => 'Find out how you can help Bolsio become better and better';

	/// en: 'Rate us'
	String get rate_us => 'Rate us';

	/// en: 'Any rate is welcome!'
	String get rate_us_descr => 'Any rate is welcome!';

	/// en: 'Share Bolsio'
	String get share => 'Share Bolsio';

	/// en: 'Share our app to friends and family'
	String get share_descr => 'Share our app to friends and family';

	/// en: 'Bolsio! The best personal finance app. Download it here'
	String get share_text => 'Bolsio! The best personal finance app. Download it here';

	/// en: 'Thank you!'
	String get thanks => 'Thank you!';

	/// en: 'Your contributions to Bolsio and other open source projects, big and small, make great projects like this possible. Thank you for taking the time to contribute.'
	String get thanks_long => 'Your contributions to Bolsio and other open source projects, big and small, make great projects like this possible. Thank you for taking the time to contribute.';

	/// en: 'Make a donation'
	String get donate => 'Make a donation';

	/// en: 'With your donation you will help the app continue receiving improvements. What better way than to thank the work done by inviting me to a coffee?'
	String get donate_descr => 'With your donation you will help the app continue receiving improvements. What better way than to thank the work done by inviting me to a coffee?';

	/// en: 'Donation made. Thank you very much for your contribution! ❤️'
	String get donate_success => 'Donation made. Thank you very much for your contribution! ❤️';

	/// en: 'Oops! It seems there was an error receiving your payment'
	String get donate_err => 'Oops! It seems there was an error receiving your payment';

	/// en: 'Report bugs, leave suggestions...'
	String get report => 'Report bugs, leave suggestions...';
}

// Path: onboarding.restricted_settings
class TranslationsOnboardingRestrictedSettingsEn {
	TranslationsOnboardingRestrictedSettingsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Allow restricted settings'
	String get title => 'Allow restricted settings';

	/// en: 'Android blocks some permissions for apps installed outside Play Store. We'll fix it in 3 taps.'
	String get subtitle => 'Android blocks some permissions for apps installed outside Play Store. We\'ll fix it in 3 taps.';

	/// en: 'Tap the ⋮ menu in the top-right.'
	String get step1 => 'Tap the ⋮ menu in the top-right.';

	/// en: 'Select "Allow restricted settings".'
	String get step2 => 'Select "Allow restricted settings".';

	/// en: 'Toggle it on and return to Bolsio.'
	String get step3 => 'Toggle it on and return to Bolsio.';

	/// en: 'Scroll to the bottom of the page.'
	String get step1_xiaomi => 'Scroll to the bottom of the page.';

	/// en: 'Toggle on "Allow restricted settings".'
	String get step2_xiaomi => 'Toggle on "Allow restricted settings".';

	/// en: 'Open app info'
	String get cta_primary => 'Open app info';

	/// en: 'Skip for now'
	String get cta_skip => 'Skip for now';

	/// en: 'Done, continue'
	String get cta_done => 'Done, continue';

	/// en: 'If you already enabled it, open app info again.'
	String get still_blocked_hint => 'If you already enabled it, open app info again.';

	/// en: 'Done, settings unlocked'
	String get success_toast => 'Done, settings unlocked';
}

// Path: general.time.ranges
class TranslationsGeneralTimeRangesEn {
	TranslationsGeneralTimeRangesEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Time range'
	String get display => 'Time range';

	/// en: 'Repeats'
	String get it_repeat => 'Repeats';

	/// en: 'Ends'
	String get it_ends => 'Ends';

	/// en: 'Forever'
	String get forever => 'Forever';

	late final TranslationsGeneralTimeRangesTypesEn types = TranslationsGeneralTimeRangesTypesEn.internal(_root);

	/// en: '(one) {Every {{range}}} (other) {Every {{n}} {{range}}}'
	String each_range({required num n, required Object range}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Every ${range}',
		other: 'Every ${n} ${range}',
	);

	/// en: '(one) {Every {{range}} until {{day}}} (other) {Every {{n}} {{range}} until {{day}}}'
	String each_range_until_date({required num n, required Object range, required Object day}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Every ${range} until ${day}',
		other: 'Every ${n} ${range} until ${day}',
	);

	/// en: '(one) {Every {{range}} {{limit}} times} (other) {Every {{n}} {{range}} {{limit}} times}'
	String each_range_until_times({required num n, required Object range, required Object limit}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Every ${range} ${limit} times',
		other: 'Every ${n} ${range} ${limit} times',
	);

	/// en: '(one) {Every {{range}} once} (other) {Every {{n}} {{range}} once}'
	String each_range_until_once({required num n, required Object range}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Every ${range} once',
		other: 'Every ${n} ${range} once',
	);

	/// en: '(one) {Month} (other) {Months}'
	String month({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Month',
		other: 'Months',
	);

	/// en: '(one) {Year} (other) {Years}'
	String year({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Year',
		other: 'Years',
	);

	/// en: '(one) {Day} (other) {Days}'
	String day({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Day',
		other: 'Days',
	);

	/// en: '(one) {Week} (other) {Weeks}'
	String week({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Week',
		other: 'Weeks',
	);
}

// Path: general.time.periodicity
class TranslationsGeneralTimePeriodicityEn {
	TranslationsGeneralTimePeriodicityEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Recurrence'
	String get display => 'Recurrence';

	/// en: 'No repeat'
	String get no_repeat => 'No repeat';

	/// en: '(one) {Repetition} (other) {Repetitions}'
	String repeat({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Repetition',
		other: 'Repetitions',
	);

	/// en: 'Daily'
	String get diary => 'Daily';

	/// en: 'Monthly'
	String get monthly => 'Monthly';

	/// en: 'Annually'
	String get annually => 'Annually';

	/// en: 'Quarterly'
	String get quaterly => 'Quarterly';

	/// en: 'Weekly'
	String get weekly => 'Weekly';

	/// en: 'Custom'
	String get custom => 'Custom';

	/// en: 'Always'
	String get infinite => 'Always';
}

// Path: general.time.current
class TranslationsGeneralTimeCurrentEn {
	TranslationsGeneralTimeCurrentEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'This month'
	String get monthly => 'This month';

	/// en: 'This year'
	String get annually => 'This year';

	/// en: 'This quarter'
	String get quaterly => 'This quarter';

	/// en: 'This week'
	String get weekly => 'This week';

	/// en: 'For ever'
	String get infinite => 'For ever';

	/// en: 'Custom Range'
	String get custom => 'Custom Range';

	/// en: 'Today'
	String get diary => 'Today';
}

// Path: general.time.all
class TranslationsGeneralTimeAllEn {
	TranslationsGeneralTimeAllEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Every day'
	String get diary => 'Every day';

	/// en: 'Every month'
	String get monthly => 'Every month';

	/// en: 'Every year'
	String get annually => 'Every year';

	/// en: 'Every quarterly'
	String get quaterly => 'Every quarterly';

	/// en: 'Every week'
	String get weekly => 'Every week';
}

// Path: home.dashboard_widgets.total_balance_summary
class TranslationsHomeDashboardWidgetsTotalBalanceSummaryEn {
	TranslationsHomeDashboardWidgetsTotalBalanceSummaryEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Total balance'
	String get name => 'Total balance';

	/// en: 'Your overall balance with currency conversion.'
	String get description => 'Your overall balance with currency conversion.';
}

// Path: home.dashboard_widgets.account_carousel
class TranslationsHomeDashboardWidgetsAccountCarouselEn {
	TranslationsHomeDashboardWidgetsAccountCarouselEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'My accounts'
	String get name => 'My accounts';

	/// en: 'Quick access to each of your accounts.'
	String get description => 'Quick access to each of your accounts.';
}

// Path: home.dashboard_widgets.income_expense_period
class TranslationsHomeDashboardWidgetsIncomeExpensePeriodEn {
	TranslationsHomeDashboardWidgetsIncomeExpensePeriodEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Income & expenses'
	String get name => 'Income & expenses';

	/// en: 'Net income and expenses for the active period.'
	String get description => 'Net income and expenses for the active period.';
}

// Path: home.dashboard_widgets.recent_transactions
class TranslationsHomeDashboardWidgetsRecentTransactionsEn {
	TranslationsHomeDashboardWidgetsRecentTransactionsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Recent transactions'
	String get name => 'Recent transactions';

	/// en: 'The latest movements across your accounts.'
	String get description => 'The latest movements across your accounts.';
}

// Path: home.dashboard_widgets.exchange_rate_card
class TranslationsHomeDashboardWidgetsExchangeRateCardEn {
	TranslationsHomeDashboardWidgetsExchangeRateCardEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Exchange rates'
	String get name => 'Exchange rates';

	/// en: 'USD ↔ VES rates from BCV and Paralelo.'
	String get description => 'USD ↔ VES rates from BCV and Paralelo.';

	/// en: 'Show rates in'
	String get pivot_label => 'Show rates in';

	/// en: 'Automatic'
	String get pivot_auto => 'Automatic';

	/// en: '1 unit of each currency = N units of the chosen currency.'
	String get pivot_help => '1 unit of each currency = N units of the chosen currency.';
}

// Path: home.dashboard_widgets.quick_use
class TranslationsHomeDashboardWidgetsQuickUseEn {
	TranslationsHomeDashboardWidgetsQuickUseEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Quick actions'
	String get name => 'Quick actions';

	/// en: 'One-tap shortcuts you choose.'
	String get description => 'One-tap shortcuts you choose.';
}

// Path: home.dashboard_widgets.pending_imports_alert
class TranslationsHomeDashboardWidgetsPendingImportsAlertEn {
	TranslationsHomeDashboardWidgetsPendingImportsAlertEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Pending imports'
	String get name => 'Pending imports';

	/// en: 'Movements waiting for your review.'
	String get description => 'Movements waiting for your review.';
}

// Path: calculator.keypad.a11y
class TranslationsCalculatorKeypadA11yEn {
	TranslationsCalculatorKeypadA11yEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Digit {{n}}'
	String digit_n({required Object n}) => 'Digit ${n}';

	/// en: 'Decimal separator'
	String get decimal => 'Decimal separator';

	/// en: 'Delete'
	String get backspace => 'Delete';

	/// en: 'Clear'
	String get clear => 'Clear';

	/// en: 'Add'
	String get plus => 'Add';

	/// en: 'Subtract'
	String get minus => 'Subtract';

	/// en: 'Equals'
	String get equals => 'Equals';
}

// Path: financial_health.review.descr
class TranslationsFinancialHealthReviewDescrEn {
	TranslationsFinancialHealthReviewDescrEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'It looks like we don't have enough expenses to calculate your financial health. Add some expenses/incomes in this period to allow us to help you!'
	String get insufficient_data => 'It looks like we don\'t have enough expenses to calculate your financial health. Add some expenses/incomes in this period to allow us to help you!';

	/// en: 'Congratulations! Your financial health is tremendous. We hope you continue your good streak and continue learning with Bolsio'
	String get very_good => 'Congratulations! Your financial health is tremendous. We hope you continue your good streak and continue learning with Bolsio';

	/// en: 'Great! Your financial health is good. Visit the analysis tab to see how to save even more!'
	String get good => 'Great! Your financial health is good. Visit the analysis tab to see how to save even more!';

	/// en: 'Your financial health is more or less in the average of the rest of the population for this period'
	String get normal => 'Your financial health is more or less in the average of the rest of the population for this period';

	/// en: 'It seems that your financial situation is not the best yet. Explore the rest of the charts to learn more about your finances'
	String get bad => 'It seems that your financial situation is not the best yet. Explore the rest of the charts to learn more about your finances';

	/// en: 'Hmm, your financial health is far below what it should be. Explore the rest of the charts to learn more about your finances'
	String get very_bad => 'Hmm, your financial health is far below what it should be. Explore the rest of the charts to learn more about your finances';
}

// Path: financial_health.savings_percentage.text
class TranslationsFinancialHealthSavingsPercentageTextEn {
	TranslationsFinancialHealthSavingsPercentageTextEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Congratulations! You have managed to save <b>{{value}}%</b> of your income during this period. It seems that you are already an expert, keep up the good work!'
	String good({required Object value}) => 'Congratulations! You have managed to save <b>${value}%</b> of your income during this period. It seems that you are already an expert, keep up the good work!';

	/// en: 'Congratulations, you have managed to save <b>{{value}}%</b> of your income during this period.'
	String normal({required Object value}) => 'Congratulations, you have managed to save <b>${value}%</b> of your income during this period.';

	/// en: 'You have managed to save <b>{{value}}%</b> of your income during this period. However, we think you can still do much more!'
	String bad({required Object value}) => 'You have managed to save <b>${value}%</b> of your income during this period. However, we think you can still do much more!';

	/// en: 'Wow, you haven't managed to save anything during this period.'
	String get very_bad => 'Wow, you haven\'t managed to save anything during this period.';
}

// Path: transaction.list.bulk_edit
class TranslationsTransactionListBulkEditEn {
	TranslationsTransactionListBulkEditEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Edit dates'
	String get dates => 'Edit dates';

	/// en: 'Edit categories'
	String get categories => 'Edit categories';

	/// en: 'Edit statuses'
	String get status => 'Edit statuses';
}

// Path: transaction.filters.saved
class TranslationsTransactionFiltersSavedEn {
	TranslationsTransactionFiltersSavedEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Saved filters'
	String get title => 'Saved filters';

	/// en: 'New Filter'
	String get new_title => 'New Filter';

	/// en: 'Edit Filter'
	String get edit_title => 'Edit Filter';

	/// en: 'Filter Name'
	String get name_label => 'Filter Name';

	/// en: 'My custom filter'
	String get name_hint => 'My custom filter';

	/// en: 'Save Filter'
	String get save_dialog_title => 'Save Filter';

	/// en: 'Save current filter'
	String get save_tooltip => 'Save current filter';

	/// en: 'Load saved filter'
	String get load_tooltip => 'Load saved filter';

	/// en: 'No saved filters found'
	String get empty_title => 'No saved filters found';

	/// en: 'Save filters here to quickly access them later.'
	String get empty_description => 'Save filters here to quickly access them later.';

	/// en: 'Filter saved successfully'
	String get save_success => 'Filter saved successfully';

	/// en: 'Filter deleted successfully'
	String get delete_success => 'Filter deleted successfully';
}

// Path: transaction.form.validators
class TranslationsTransactionFormValidatorsEn {
	TranslationsTransactionFormValidatorsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'The value of a transaction cannot be equal to zero'
	String get zero => 'The value of a transaction cannot be equal to zero';

	/// en: 'The selected date is after the current one. The transaction will be added as pending'
	String get date_max => 'The selected date is after the current one. The transaction will be added as pending';

	/// en: 'You cannot create a transaction whose date is before the creation date of the account it belongs to'
	String get date_after_account_creation => 'You cannot create a transaction whose date is before the creation date of the account it belongs to';

	/// en: 'The monetary value of a transfer cannot be negative'
	String get negative_transfer => 'The monetary value of a transfer cannot be negative';

	/// en: 'The origin and the destination account cannot be the same'
	String get transfer_between_same_accounts => 'The origin and the destination account cannot be the same';

	/// en: 'Select a category before saving'
	String get category_required => 'Select a category before saving';
}

// Path: transaction.receipt_import.error
class TranslationsTransactionReceiptImportErrorEn {
	TranslationsTransactionReceiptImportErrorEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'No text was detected in the image'
	String get ocr_empty => 'No text was detected in the image';

	/// en: 'AI processing failed, local extraction was used'
	String get ai_failed => 'AI processing failed, local extraction was used';

	/// en: 'The image appears to be corrupted'
	String get image_corrupt => 'The image appears to be corrupted';

	/// en: 'Could not detect an amount'
	String get no_amount => 'Could not detect an amount';

	/// en: 'Ambiguous currency, please review it before continuing'
	String get ambiguous_currency => 'Ambiguous currency, please review it before continuing';
}

// Path: transaction.receipt_import.field
class TranslationsTransactionReceiptImportFieldEn {
	TranslationsTransactionReceiptImportFieldEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Amount'
	String get amount => 'Amount';

	/// en: 'Currency'
	String get currency => 'Currency';

	/// en: 'Date'
	String get date => 'Date';

	/// en: 'Type'
	String get type => 'Type';

	/// en: 'Counterparty'
	String get counterparty => 'Counterparty';

	/// en: 'Reference'
	String get reference => 'Reference';
}

// Path: transfer.form.value_in_destiny
class TranslationsTransferFormValueInDestinyEn {
	TranslationsTransferFormValueInDestinyEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Amount transferred at destination'
	String get title => 'Amount transferred at destination';

	/// en: '{{amount}} to target account'
	String amount_short({required Object amount}) => '${amount} to target account';
}

// Path: budgets.progress.labels
class TranslationsBudgetsProgressLabelsEn {
	TranslationsBudgetsProgressLabelsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'On track'
	String get active_on_track => 'On track';

	/// en: 'Overspending'
	String get active_overspending => 'Overspending';

	/// en: 'Active'
	String get active_indeterminate => 'Active';

	/// en: 'Achieved'
	String get success => 'Achieved';

	/// en: 'Budget exceeded'
	String get fail => 'Budget exceeded';
}

// Path: budgets.progress.description
class TranslationsBudgetsProgressDescriptionEn {
	TranslationsBudgetsProgressDescriptionEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'You can spend {{ dailyAmount }} per day for the remaining {{ remainingDays }} days'
	String active_on_track({required Object dailyAmount, required Object remainingDays}) => 'You can spend ${dailyAmount} per day for the remaining ${remainingDays} days';

	/// en: 'To get back on track, you should limit your spending to {{ dailyAmount }} per day for the remaining {{ remainingDays }} days'
	String active_overspending({required Object dailyAmount, required Object remainingDays}) => 'To get back on track, you should limit your spending to ${dailyAmount} per day for the remaining ${remainingDays} days';

	/// en: 'You have {{ amount }} left to spend.'
	String active_indeterminate({required Object amount}) => 'You have ${amount} left to spend.';

	/// en: 'You have already exceeded your budget limit by {{ amount }}. If you don't find any incomes for this budget, you should stop spending for the rest of its period'
	String active_exceeded({required Object amount}) => 'You have already exceeded your budget limit by ${amount}. If you don\'t find any incomes for this budget, you should stop spending for the rest of its period';

	/// en: 'Great job! This budget has already finish successfully. Keep creating budgets to manage your expenses'
	String get success => 'Great job! This budget has already finish successfully. Keep creating budgets to manage your expenses';

	/// en: 'You exceeded the budget by {{ amount }}. Try to be more careful next time!'
	String fail({required Object amount}) => 'You exceeded the budget by ${amount}. Try to be more careful next time!';
}

// Path: goals.type.income
class TranslationsGoalsTypeIncomeEn {
	TranslationsGoalsTypeIncomeEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Savings Goal'
	String get title => 'Savings Goal';

	/// en: 'Ideal for saving money. You succeed when the balance goes above your target.'
	String get descr => 'Ideal for saving money. You succeed when the balance goes above your target.';
}

// Path: goals.type.expense
class TranslationsGoalsTypeExpenseEn {
	TranslationsGoalsTypeExpenseEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Spending Goal'
	String get title => 'Spending Goal';

	/// en: 'Track how much you spend and aim to reach a target amount. Works good for donations, charity, leisure spending...'
	String get descr => 'Track how much you spend and aim to reach a target amount. Works good for donations, charity, leisure spending...';
}

// Path: goals.progress.labels
class TranslationsGoalsProgressLabelsEn {
	TranslationsGoalsProgressLabelsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'On track'
	String get active_on_track => 'On track';

	/// en: 'Behind schedule'
	String get active_behind_schedule => 'Behind schedule';

	/// en: 'Active'
	String get active_indeterminate => 'Active';

	/// en: 'Goal reached'
	String get success => 'Goal reached';

	/// en: 'Goal failed'
	String get fail => 'Goal failed';
}

// Path: goals.progress.description
class TranslationsGoalsProgressDescriptionEn {
	TranslationsGoalsProgressDescriptionEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'You are on track to seek your goal! You have to save {{ dailyAmount }} per day for the remaining {{ remainingDays }} days'
	String active_on_track({required Object dailyAmount, required Object remainingDays}) => 'You are on track to seek your goal! You have to save ${dailyAmount} per day for the remaining ${remainingDays} days';

	/// en: 'You are behind schedule. You have to save {{ dailyAmount }} per day to reach your goal in {{ remainingDays }} days'
	String active_behind_schedule({required Object dailyAmount, required Object remainingDays}) => 'You are behind schedule. You have to save ${dailyAmount} per day to reach your goal in ${remainingDays} days';

	/// en: 'You need {{ amount }} more to reach your goal.'
	String active_indeterminate({required Object amount}) => 'You need ${amount} more to reach your goal.';

	/// en: 'Congratulations! You reached your goal.'
	String get success => 'Congratulations! You reached your goal.';

	/// en: 'You missed your goal by {{ amount }}.'
	String fail({required Object amount}) => 'You missed your goal by ${amount}.';
}

// Path: debts.form.from_transaction
class TranslationsDebtsFormFromTransactionEn {
	TranslationsDebtsFormFromTransactionEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'From a transaction'
	String get title => 'From a transaction';

	/// en: 'Tap to select a transaction'
	String get tap_to_select => 'Tap to select a transaction';
}

// Path: debts.form.from_amount
class TranslationsDebtsFormFromAmountEn {
	TranslationsDebtsFormFromAmountEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'From an initial amount'
	String get title => 'From an initial amount';

	/// en: 'This amount will not be taken into account for statistics as an expense/income. It will be used to calculate balances and net worth'
	String get description => 'This amount will not be taken into account for statistics as an expense/income. It will be used to calculate balances and net worth';
}

// Path: debts.actions.edit
class TranslationsDebtsActionsEditEn {
	TranslationsDebtsActionsEditEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Edit debt'
	String get title => 'Edit debt';

	/// en: 'Debt edited successfully'
	String get success => 'Debt edited successfully';
}

// Path: debts.actions.delete
class TranslationsDebtsActionsDeleteEn {
	TranslationsDebtsActionsDeleteEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Delete this debt?'
	String get warning_header => 'Delete this debt?';

	/// en: 'This action cannot be undone. Linked transactions will not be deleted but will no longer be associated with this debt.'
	String get warning_text => 'This action cannot be undone. Linked transactions will not be deleted but will no longer be associated with this debt.';
}

// Path: debts.actions.add_register
class TranslationsDebtsActionsAddRegisterEn {
	TranslationsDebtsActionsAddRegisterEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Add movement'
	String get title => 'Add movement';

	/// en: 'Movement added successfully'
	String get success => 'Movement added successfully';

	/// en: 'Add register'
	String get fab_label => 'Add register';

	/// en: 'Add register to this debt'
	String get modal_title => 'Add register to this debt';

	/// en: 'Choose one of the following options to link a transaction to this debt'
	String get modal_subtitle => 'Choose one of the following options to link a transaction to this debt';
}

// Path: debts.actions.link_transaction
class TranslationsDebtsActionsLinkTransactionEn {
	TranslationsDebtsActionsLinkTransactionEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Link existing transaction'
	String get title => 'Link existing transaction';

	/// en: 'Choose an existing record to link it to this debt'
	String get description => 'Choose an existing record to link it to this debt';

	/// en: 'Transaction linked to debt'
	String get success => 'Transaction linked to debt';

	/// en: 'You are creating a transaction linked to the debt <b>{{ name }}</b>'
	String creating({required Object name}) => 'You are creating a transaction linked to the debt <b>${name}</b>';
}

// Path: debts.actions.unlink_transaction
class TranslationsDebtsActionsUnlinkTransactionEn {
	TranslationsDebtsActionsUnlinkTransactionEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Unlink from debt'
	String get title => 'Unlink from debt';

	/// en: 'This transaction will no longer be associated with this debt.'
	String get warning_text => 'This transaction will no longer be associated with this debt.';

	/// en: 'Transaction unlinked from debt'
	String get success => 'Transaction unlinked from debt';
}

// Path: debts.actions.new_transaction
class TranslationsDebtsActionsNewTransactionEn {
	TranslationsDebtsActionsNewTransactionEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Add new transaction'
	String get title => 'Add new transaction';

	/// en: 'Manually add or reduce the debt by creating a new transaction linked to this debt'
	String get description => 'Manually add or reduce the debt by creating a new transaction linked to this debt';
}

// Path: debts.actions.create
class TranslationsDebtsActionsCreateEn {
	TranslationsDebtsActionsCreateEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Create debt'
	String get title => 'Create debt';

	/// en: 'Debt created successfully'
	String get success => 'Debt created successfully';
}

// Path: backup.import.manual_import
class TranslationsBackupImportManualImportEn {
	TranslationsBackupImportManualImportEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Manual import'
	String get title => 'Manual import';

	/// en: 'Import transactions from a .csv file manually'
	String get descr => 'Import transactions from a .csv file manually';

	/// en: 'Default account'
	String get default_account => 'Default account';

	/// en: 'Remove default account'
	String get remove_default_account => 'Remove default account';

	/// en: 'Default Category'
	String get default_category => 'Default Category';

	/// en: 'Select a column from the .csv'
	String get select_a_column => 'Select a column from the .csv';

	List<String> get steps => [
		'Select your file',
		'Column for quantity',
		'Column for account',
		'Column for category',
		'Column for date',
		'other columns',
	];
	List<String> get steps_descr => [
		'Select a .csv file from your device. Make sure it has a first row that describes the name of each column',
		'Select the column where the value of each transaction is specified. Use negative values for expenses and positive values for income.',
		'Select the column where the account to which each transaction belongs is specified. You can also select a default account in case we cannot find the account you want. If a default account is not specified, we will create one with the same name ',
		'Specify the column where the transaction category name is located. You must specify a default category so that we assign this category to transactions, in case the category cannot be found',
		'Select the column where the date of each transaction is specified. If not specified, transactions will be created with the current date',
		'Specifies the columns for other optional transaction attributes',
	];

	/// en: 'Successfully imported {{x}} transactions'
	String success({required Object x}) => 'Successfully imported ${x} transactions';
}

// Path: settings.general.language
class TranslationsSettingsGeneralLanguageEn {
	TranslationsSettingsGeneralLanguageEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Language and texts'
	String get section => 'Language and texts';

	/// en: 'App language'
	String get title => 'App language';

	/// en: 'Language in which the texts will be displayed in the app'
	String get descr => 'Language in which the texts will be displayed in the app';

	/// en: 'If you want to collaborate with the translations of this app, you can consult <a href='__BOLSIO_GITHUB_URL__/tree/main/lib/i18n'>our guide</a>'
	String get help => 'If you want to collaborate with the translations of this app, you can consult <a href=\'__BOLSIO_GITHUB_URL__/tree/main/lib/i18n\'>our guide</a>';
}

// Path: settings.general.locale
class TranslationsSettingsGeneralLocaleEn {
	TranslationsSettingsGeneralLocaleEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Region'
	String get title => 'Region';

	/// en: 'System'
	String get auto => 'System';

	/// en: 'Set the format to use for dates, numbers...'
	String get descr => 'Set the format to use for dates, numbers...';

	/// en: 'When changing region the app will update'
	String get warn => 'When changing region the app will update';

	/// en: 'First day of week'
	String get first_day_of_week => 'First day of week';
}

// Path: settings.security.biometric
class TranslationsSettingsSecurityBiometricEn {
	TranslationsSettingsSecurityBiometricEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Use fingerprint/biometrics'
	String get title => 'Use fingerprint/biometrics';

	/// en: 'Require authentication when opening the app'
	String get descr => 'Require authentication when opening the app';

	/// en: 'Biometric lock'
	String get section_title => 'Biometric lock';
}

// Path: settings.hidden_mode.pin
class TranslationsSettingsHiddenModePinEn {
	TranslationsSettingsHiddenModePinEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Create your PIN'
	String get setup_title => 'Create your PIN';

	/// en: 'This PIN will unlock your hidden accounts'
	String get setup_subtitle => 'This PIN will unlock your hidden accounts';

	/// en: 'Confirm your PIN'
	String get confirm_title => 'Confirm your PIN';

	/// en: 'Enter your PIN'
	String get unlock_title => 'Enter your PIN';

	/// en: 'Enter your current PIN'
	String get change_old_title => 'Enter your current PIN';

	/// en: 'Create a new PIN'
	String get change_new_title => 'Create a new PIN';

	/// en: 'Confirm the new PIN'
	String get change_confirm_title => 'Confirm the new PIN';

	/// en: 'Confirm your PIN to disable Hidden Mode'
	String get disable_title => 'Confirm your PIN to disable Hidden Mode';

	/// en: 'PINs do not match'
	String get mismatch => 'PINs do not match';

	/// en: 'Incorrect PIN'
	String get incorrect => 'Incorrect PIN';

	/// en: 'Too many attempts. Try again in {{seconds}}s'
	String too_many_attempts({required Object seconds}) => 'Too many attempts. Try again in ${seconds}s';

	/// en: 'Use fingerprint'
	String get use_biometric => 'Use fingerprint';

	/// en: 'Unlock Bolsio'
	String get biometric_reason => 'Unlock Bolsio';

	/// en: 'PIN updated'
	String get pin_changed => 'PIN updated';

	/// en: 'Full view unlocked'
	String get unlocked => 'Full view unlocked';
}

// Path: settings.transactions.style
class TranslationsSettingsTransactionsStyleEn {
	TranslationsSettingsTransactionsStyleEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Transaction style'
	String get title => 'Transaction style';

	/// en: 'Configure how transactions look in the different lists of the app'
	String get subtitle => 'Configure how transactions look in the different lists of the app';

	/// en: 'Show Tags'
	String get show_tags => 'Show Tags';

	/// en: 'Show Time'
	String get show_time => 'Show Time';
}

// Path: settings.transactions.swipe_actions
class TranslationsSettingsTransactionsSwipeActionsEn {
	TranslationsSettingsTransactionsSwipeActionsEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Swipe actions'
	String get title => 'Swipe actions';

	/// en: 'Choose what action will be triggered when you swipe a transaction item in the list using this swipe direction'
	String get choose_description => 'Choose what action will be triggered when you swipe a transaction item in the list using this swipe direction';

	/// en: 'Swipe left'
	String get swipe_left => 'Swipe left';

	/// en: 'Swipe right'
	String get swipe_right => 'Swipe right';

	/// en: 'No action'
	String get none => 'No action';

	/// en: 'Toggle reconciled'
	String get toggle_reconciled => 'Toggle reconciled';

	/// en: 'Toggle pending'
	String get toggle_pending => 'Toggle pending';

	/// en: 'Toggle voided'
	String get toggle_voided => 'Toggle voided';

	/// en: 'Toggle unreconciled'
	String get toggle_unreconciled => 'Toggle unreconciled';

	/// en: 'Remove status'
	String get remove_status => 'Remove status';
}

// Path: settings.transactions.default_values
class TranslationsSettingsTransactionsDefaultValuesEn {
	TranslationsSettingsTransactionsDefaultValuesEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Default Form Values'
	String get title => 'Default Form Values';

	/// en: 'New Transaction: Default Form Values'
	String get page_title => 'New Transaction: Default Form Values';

	/// en: 'Reuse Last Transaction Values'
	String get reuse_last_transaction => 'Reuse Last Transaction Values';

	/// en: 'Automatically fill the form with some values from the last created transaction'
	String get reuse_last_transaction_descr => 'Automatically fill the form with some values from the last created transaction';

	/// en: 'Fields to reuse'
	String get fields_to_reuse => 'Fields to reuse';

	/// en: 'Select the fields that should be pre-filled with the values from the last created transaction.'
	String get reuse_last_values_modal_descr => 'Select the fields that should be pre-filled with the values from the last created transaction.';

	/// en: 'Default Values'
	String get default_values_separator => 'Default Values';

	/// en: 'Default Category'
	String get default_category => 'Default Category';

	/// en: 'Default Status'
	String get default_status => 'Default Status';

	/// en: 'Default Tags'
	String get default_tags => 'Default Tags';

	/// en: 'No tags selected'
	String get no_tags_selected => 'No tags selected';
}

// Path: settings.transactions.default_type
class TranslationsSettingsTransactionsDefaultTypeEn {
	TranslationsSettingsTransactionsDefaultTypeEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Default Type'
	String get title => 'Default Type';

	/// en: 'Select Default Type'
	String get modal_title => 'Select Default Type';
}

// Path: settings.appearance.theme
class TranslationsSettingsAppearanceThemeEn {
	TranslationsSettingsAppearanceThemeEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Theme'
	String get title => 'Theme';

	/// en: 'System'
	String get auto => 'System';

	/// en: 'Light'
	String get light => 'Light';

	/// en: 'Dark'
	String get dark => 'Dark';
}

// Path: more.about_us.legal
class TranslationsMoreAboutUsLegalEn {
	TranslationsMoreAboutUsLegalEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Legal information'
	String get display => 'Legal information';

	/// en: 'Privacy policy'
	String get privacy => 'Privacy policy';

	/// en: 'Terms of use'
	String get terms => 'Terms of use';

	/// en: 'Licenses'
	String get licenses => 'Licenses';
}

// Path: more.about_us.project
class TranslationsMoreAboutUsProjectEn {
	TranslationsMoreAboutUsProjectEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Project'
	String get display => 'Project';

	/// en: 'Collaborators'
	String get contributors => 'Collaborators';

	/// en: 'All the developers who have made Bolsio grow'
	String get contributors_descr => 'All the developers who have made Bolsio grow';

	/// en: 'Contact us'
	String get contact => 'Contact us';
}

// Path: general.time.ranges.types
class TranslationsGeneralTimeRangesTypesEn {
	TranslationsGeneralTimeRangesTypesEn.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Cycles'
	String get cycle => 'Cycles';

	/// en: 'Last days'
	String get last_days => 'Last days';

	/// en: '{{x}} previous days'
	String last_days_form({required Object x}) => '${x} previous days';

	/// en: 'Always'
	String get all => 'Always';

	/// en: 'Custom range'
	String get date_range => 'Custom range';
}

/// The flat map containing all translations for locale <en>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on Translations {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'ui_actions.cancel' => 'Cancel',
			'ui_actions.confirm' => 'Confirm',
			'ui_actions.continue_text' => 'Continue',
			'ui_actions.save' => 'Save',
			'ui_actions.save_changes' => 'Save changes',
			'ui_actions.close_and_save' => 'Save and close',
			'ui_actions.add' => 'Add',
			'ui_actions.edit' => 'Edit',
			'ui_actions.delete' => 'Delete',
			'ui_actions.see_more' => 'See more',
			'ui_actions.select_all' => 'Select all',
			'ui_actions.deselect_all' => 'Deselect all',
			'ui_actions.select' => 'Select',
			'ui_actions.search' => 'Search',
			'ui_actions.filter' => 'Filter',
			'ui_actions.reset' => 'Reset',
			'ui_actions.submit' => 'Submit',
			'ui_actions.next' => 'Next',
			'ui_actions.previous' => 'Previous',
			'ui_actions.back' => 'Back',
			'ui_actions.reload' => 'Reload',
			'ui_actions.view' => 'View',
			'ui_actions.download' => 'Download',
			'ui_actions.upload' => 'Upload',
			'ui_actions.retry' => 'Retry',
			'ui_actions.copy' => 'Copy',
			'ui_actions.paste' => 'Paste',
			'ui_actions.undo' => 'Undo',
			'ui_actions.redo' => 'Redo',
			'ui_actions.open' => 'Open',
			'ui_actions.close' => 'Close',
			'ui_actions.apply' => 'Apply',
			'ui_actions.discard' => 'Discard',
			'ui_actions.refresh' => 'Refresh',
			'ui_actions.share' => 'Share',
			'general.or' => 'or',
			'general.understood' => 'Understood',
			'general.unspecified' => 'Unspecified',
			'general.quick_actions' => 'Quick actions',
			'general.details' => 'Details',
			'general.balance' => 'Balance',
			'general.account' => 'Account',
			'general.accounts' => 'Accounts',
			'general.categories' => 'Categories',
			'general.category' => 'Category',
			'general.today' => 'Today',
			'general.yesterday' => 'Yesterday',
			'general.filters' => 'Filters',
			'general.empty_warn' => 'Ops! This is very empty',
			'general.search_no_results' => 'No items match your search criteria',
			'general.insufficient_data' => 'Insufficient data',
			'general.show_more_fields' => 'Show more fields',
			'general.show_less_fields' => 'Show less fields',
			'general.tap_to_search' => 'Tap to search',
			'general.delete_success' => 'Item deleted successfully',
			'general.leave_without_saving.title' => 'Leave without saving?',
			'general.leave_without_saving.message' => 'You have unsaved changes, are you sure you want to leave without saving them?',
			'general.clipboard.success' => ({required Object x}) => '${x} copied to the clipboard',
			'general.clipboard.error' => 'Error copying',
			'general.time.start_date' => 'Start date',
			'general.time.end_date' => 'End date',
			'general.time.from_date' => 'From date',
			'general.time.until_date' => 'Until date',
			'general.time.date' => 'Date',
			'general.time.datetime' => 'Datetime',
			'general.time.time' => 'Time',
			'general.time.each' => 'Each',
			'general.time.after' => 'After',
			'general.time.ranges.display' => 'Time range',
			'general.time.ranges.it_repeat' => 'Repeats',
			'general.time.ranges.it_ends' => 'Ends',
			'general.time.ranges.forever' => 'Forever',
			'general.time.ranges.types.cycle' => 'Cycles',
			'general.time.ranges.types.last_days' => 'Last days',
			'general.time.ranges.types.last_days_form' => ({required Object x}) => '${x} previous days',
			'general.time.ranges.types.all' => 'Always',
			'general.time.ranges.types.date_range' => 'Custom range',
			'general.time.ranges.each_range' => ({required num n, required Object range}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Every ${range}', other: 'Every ${n} ${range}', ), 
			'general.time.ranges.each_range_until_date' => ({required num n, required Object range, required Object day}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Every ${range} until ${day}', other: 'Every ${n} ${range} until ${day}', ), 
			'general.time.ranges.each_range_until_times' => ({required num n, required Object range, required Object limit}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Every ${range} ${limit} times', other: 'Every ${n} ${range} ${limit} times', ), 
			'general.time.ranges.each_range_until_once' => ({required num n, required Object range}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Every ${range} once', other: 'Every ${n} ${range} once', ), 
			'general.time.ranges.month' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Month', other: 'Months', ), 
			'general.time.ranges.year' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Year', other: 'Years', ), 
			'general.time.ranges.day' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Day', other: 'Days', ), 
			'general.time.ranges.week' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Week', other: 'Weeks', ), 
			'general.time.periodicity.display' => 'Recurrence',
			'general.time.periodicity.no_repeat' => 'No repeat',
			'general.time.periodicity.repeat' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Repetition', other: 'Repetitions', ), 
			'general.time.periodicity.diary' => 'Daily',
			'general.time.periodicity.monthly' => 'Monthly',
			'general.time.periodicity.annually' => 'Annually',
			'general.time.periodicity.quaterly' => 'Quarterly',
			'general.time.periodicity.weekly' => 'Weekly',
			'general.time.periodicity.custom' => 'Custom',
			'general.time.periodicity.infinite' => 'Always',
			'general.time.current.monthly' => 'This month',
			'general.time.current.annually' => 'This year',
			'general.time.current.quaterly' => 'This quarter',
			'general.time.current.weekly' => 'This week',
			'general.time.current.infinite' => 'For ever',
			'general.time.current.custom' => 'Custom Range',
			'general.time.current.diary' => 'Today',
			'general.time.all.diary' => 'Every day',
			'general.time.all.monthly' => 'Every month',
			'general.time.all.annually' => 'Every year',
			'general.time.all.quaterly' => 'Every quarterly',
			'general.time.all.weekly' => 'Every week',
			'general.transaction_order.display' => 'Order transactions',
			'general.transaction_order.category' => 'By category',
			'general.transaction_order.quantity' => 'By quantity',
			'general.transaction_order.date' => 'By date',
			'general.validations.form_error' => 'Fix the indicated fields to continue',
			'general.validations.required' => 'Required field',
			'general.validations.positive' => 'Should be positive',
			'general.validations.min_number' => ({required Object x}) => 'Should be greater than ${x}',
			'general.validations.max_number' => ({required Object x}) => 'Should be less than ${x}',
			'shared.app_tagline' => '100% open, 100% free',
			'home.title' => 'Dashboard',
			'home.filter_transactions' => 'Filter transactions',
			'home.hello_day' => 'Good morning,',
			'home.hello_night' => 'Good night,',
			'home.total_balance' => 'Total balance',
			'home.my_accounts' => 'My accounts',
			'home.active_accounts' => 'Active accounts',
			'home.no_accounts' => 'No accounts created yet',
			'home.no_accounts_descr' => 'Start using all the magic of Bolsio. Create at least one account to start adding transactions',
			'home.last_transactions' => 'Last transactions',
			'home.should_create_account_header' => 'Oops!',
			'home.should_create_account_message' => 'You must have at least one no-archived account before you can start creating transactions',
			'home.dashboard_widgets.edit_banner' => 'Long-press to reorder · X to remove · + to add',
			'home.dashboard_widgets.exit_edit_mode' => 'Exit edit mode',
			'home.dashboard_widgets.edit_dashboard' => 'Edit dashboard',
			'home.dashboard_widgets.remove_widget_title' => 'Remove widget',
			'home.dashboard_widgets.remove_widget_message' => 'Remove "{name}" from your dashboard?',
			'home.dashboard_widgets.add_widget' => 'Add widget',
			'home.dashboard_widgets.recommended_badge' => 'Recommended',
			'home.dashboard_widgets.reset_to_goals_action' => 'Reset to my goals',
			'home.dashboard_widgets.reset_to_goals_confirm_title' => 'Reset dashboard?',
			'home.dashboard_widgets.reset_to_goals_confirm_message' => 'Replace your current dashboard with the layout suggested by your onboarding goals.',
			'home.dashboard_widgets.drag_handle_tooltip' => 'Long-press to reorder',
			'home.dashboard_widgets.configure_tooltip' => 'Configure',
			'home.dashboard_widgets.remove_tooltip' => 'Remove',
			'home.dashboard_widgets.total_balance_summary.name' => 'Total balance',
			'home.dashboard_widgets.total_balance_summary.description' => 'Your overall balance with currency conversion.',
			'home.dashboard_widgets.account_carousel.name' => 'My accounts',
			'home.dashboard_widgets.account_carousel.description' => 'Quick access to each of your accounts.',
			'home.dashboard_widgets.income_expense_period.name' => 'Income & expenses',
			'home.dashboard_widgets.income_expense_period.description' => 'Net income and expenses for the active period.',
			'home.dashboard_widgets.recent_transactions.name' => 'Recent transactions',
			'home.dashboard_widgets.recent_transactions.description' => 'The latest movements across your accounts.',
			'home.dashboard_widgets.exchange_rate_card.name' => 'Exchange rates',
			'home.dashboard_widgets.exchange_rate_card.description' => 'USD ↔ VES rates from BCV and Paralelo.',
			'home.dashboard_widgets.exchange_rate_card.pivot_label' => 'Show rates in',
			'home.dashboard_widgets.exchange_rate_card.pivot_auto' => 'Automatic',
			'home.dashboard_widgets.exchange_rate_card.pivot_help' => '1 unit of each currency = N units of the chosen currency.',
			'home.dashboard_widgets.quick_use.name' => 'Quick actions',
			'home.dashboard_widgets.quick_use.description' => 'One-tap shortcuts you choose.',
			'home.dashboard_widgets.pending_imports_alert.name' => 'Pending imports',
			'home.dashboard_widgets.pending_imports_alert.description' => 'Movements waiting for your review.',
			'home.quick_actions.toggle_private_mode' => 'Private mode',
			'home.quick_actions.toggle_hidden_mode' => 'Hidden mode',
			'home.quick_actions.toggle_preferred_currency' => 'Currency',
			'home.quick_actions.go_to_settings' => 'Settings',
			'home.quick_actions.new_expense_transaction' => 'New expense',
			'home.quick_actions.new_income_transaction' => 'New income',
			'home.quick_actions.new_transfer_transaction' => 'Transfer',
			'home.quick_actions.go_to_budgets' => 'Budgets',
			'home.quick_actions.go_to_reports' => 'Reports',
			'home.quick_actions.open_transactions' => 'Transactions',
			'home.quick_actions.open_exchange_rates' => 'Exchange rates',
			'home.quick_actions.go_to_calculator' => 'Calculator',
			'calculator.title' => 'Calculator',
			'calculator.settings_subtitle' => 'Quick converter USD/EUR/USDT to VES',
			'calculator.swap.a11y' => 'Invert conversion',
			'calculator.keypad.a11y.digit_n' => ({required Object n}) => 'Digit ${n}',
			'calculator.keypad.a11y.decimal' => 'Decimal separator',
			'calculator.keypad.a11y.backspace' => 'Delete',
			'calculator.keypad.a11y.clear' => 'Clear',
			'calculator.keypad.a11y.plus' => 'Add',
			'calculator.keypad.a11y.minus' => 'Subtract',
			'calculator.keypad.a11y.equals' => 'Equals',
			'calculator.source.bcv' => 'BCV',
			'calculator.source.paralelo' => 'Parallel',
			'calculator.source.promedio' => 'Average',
			'calculator.source.manual' => 'Manual',
			'calculator.source.usdt_label' => 'Parallel (USDT)',
			'calculator.source.updated_ago' => ({required Object minutes}) => '${minutes} min ago',
			'calculator.source.updated_just_now' => 'just now',
			'calculator.source.updated_unknown' => '—',
			'calculator.source.a11y_label' => ({required Object source, required Object age}) => 'Rate source: ${source}, updated ${age}',
			'calculator.manual.field_hint' => ({required Object currency}) => 'Rate per 1 ${currency}',
			'calculator.manual.field_label' => 'Manual rate',
			'calculator.manual.field_invalid' => 'Enter a value greater than 0',
			'calculator.manual.save_link' => 'Save as manual rate',
			'calculator.warn.no_rate' => 'No cached rate. Use manual mode or connect to the internet.',
			'calculator.refresh.a11y' => 'Refresh rates',
			'calculator.refresh.error' => 'Could not update rates. Showing cached values.',
			'calculator.share.action_a11y' => 'Share conversion',
			'calculator.share.footer' => 'Generated with Bolsio',
			'calculator.share.subject' => 'FX conversion',
			'calculator.share.equals_separator' => '=',
			'calculator.rate_explicit.format' => ({required Object from, required Object to, required Object amount}) => '${from} 1 = ${to} ${amount}',
			'calculator.rate_explicit.timestamp_long' => ({required Object date}) => 'Updated ${date}',
			'calculator.rate_explicit.timestamp_unknown' => 'No rate available',
			'calculator.rate_explicit.timestamp_manual' => 'Manual rate',
			'calculator.copy.tooltip' => 'Copy',
			'calculator.copy.a11y' => 'Copy amount',
			'calculator.copy.snackbar' => ({required Object value}) => '${value} copied',
			'financial_health.display' => 'Financial health',
			'financial_health.review.very_good' => ({required GenderContext context}) { switch (context) { case GenderContext.male: return 'Very good!'; case GenderContext.female: return 'Very good!'; } }, 
			'financial_health.review.good' => ({required GenderContext context}) { switch (context) { case GenderContext.male: return 'Good'; case GenderContext.female: return 'Good'; } }, 
			'financial_health.review.normal' => ({required GenderContext context}) { switch (context) { case GenderContext.male: return 'Average'; case GenderContext.female: return 'Average'; } }, 
			'financial_health.review.bad' => ({required GenderContext context}) { switch (context) { case GenderContext.male: return 'Fair'; case GenderContext.female: return 'Fair'; } }, 
			'financial_health.review.very_bad' => ({required GenderContext context}) { switch (context) { case GenderContext.male: return 'Very Bad'; case GenderContext.female: return 'Very Bad'; } }, 
			'financial_health.review.insufficient_data' => ({required GenderContext context}) { switch (context) { case GenderContext.male: return 'Insufficient data'; case GenderContext.female: return 'Insufficient data'; } }, 
			'financial_health.review.descr.insufficient_data' => 'It looks like we don\'t have enough expenses to calculate your financial health. Add some expenses/incomes in this period to allow us to help you!',
			'financial_health.review.descr.very_good' => 'Congratulations! Your financial health is tremendous. We hope you continue your good streak and continue learning with Bolsio',
			'financial_health.review.descr.good' => 'Great! Your financial health is good. Visit the analysis tab to see how to save even more!',
			'financial_health.review.descr.normal' => 'Your financial health is more or less in the average of the rest of the population for this period',
			'financial_health.review.descr.bad' => 'It seems that your financial situation is not the best yet. Explore the rest of the charts to learn more about your finances',
			'financial_health.review.descr.very_bad' => 'Hmm, your financial health is far below what it should be. Explore the rest of the charts to learn more about your finances',
			'financial_health.months_without_income.title' => 'Survival rate',
			'financial_health.months_without_income.subtitle' => 'Given your balance, amount of time you could go without income',
			'financial_health.months_without_income.text_zero' => 'You couldn\'t survive a month without income at this rate of expenses!',
			'financial_health.months_without_income.text_one' => 'You could barely survive approximately a month without income at this rate of expenses!',
			'financial_health.months_without_income.text_other' => ({required Object n}) => 'You could survive approximately <b>${n} months</b> without income at this rate of spending.',
			'financial_health.months_without_income.text_infinite' => 'You could survive approximately <b>all your life</b> without income at this rate of spending.',
			'financial_health.months_without_income.suggestion' => 'Remember that it is advisable to always keep this ratio above 5 months at least. If you see that you do not have a sufficient savings cushion, reduce unnecessary expenses.',
			'financial_health.months_without_income.insufficient_data' => 'It looks like we don\'t have enough expenses to calculate how many months you could survive without income. Enter a few transactions and come back here to check your financial health',
			'financial_health.savings_percentage.title' => 'Savings percentage',
			'financial_health.savings_percentage.subtitle' => 'What part of your income is not spent in this period',
			'financial_health.savings_percentage.text.good' => ({required Object value}) => 'Congratulations! You have managed to save <b>${value}%</b> of your income during this period. It seems that you are already an expert, keep up the good work!',
			'financial_health.savings_percentage.text.normal' => ({required Object value}) => 'Congratulations, you have managed to save <b>${value}%</b> of your income during this period.',
			'financial_health.savings_percentage.text.bad' => ({required Object value}) => 'You have managed to save <b>${value}%</b> of your income during this period. However, we think you can still do much more!',
			'financial_health.savings_percentage.text.very_bad' => 'Wow, you haven\'t managed to save anything during this period.',
			'financial_health.savings_percentage.suggestion' => 'Remember that it is advisable to save at least 15-20% of what you earn.',
			'stats.title' => 'Statistics',
			'stats.balance' => 'Balance',
			'stats.final_balance' => 'Final balance',
			'stats.balance_by_account' => 'Balance by accounts',
			'stats.balance_by_account_subtitle' => 'Where do I have most of my money?',
			'stats.balance_by_currency' => 'Balance by currency',
			'stats.balance_by_currency_subtitle' => 'How much money do I have in foreign currency?',
			'stats.balance_evolution' => 'Balance trend',
			'stats.balance_evolution_subtitle' => 'Do I have more money than before?',
			'stats.compared_to_previous_period' => 'Compared to the previous period',
			'stats.cash_flow' => 'Cash flow',
			'stats.cash_flow_subtitle' => 'Am I spending less than I earn?',
			'stats.by_periods' => 'By periods',
			'stats.by_categories' => 'By categories',
			'stats.by_tags' => 'By tags',
			'stats.distribution' => 'Distribution',
			'stats.finance_health_resume' => 'Resume',
			'stats.finance_health_breakdown' => 'Breakdown',
			'icon_selector.name' => 'Name:',
			'icon_selector.icon' => 'Icon',
			'icon_selector.color' => 'Color',
			'icon_selector.select_icon' => 'Select an icon',
			'icon_selector.select_color' => 'Select a color',
			'icon_selector.custom_color' => 'Custom color',
			'icon_selector.current_color_selection' => 'Current selection',
			'icon_selector.select_account_icon' => 'Identify your account',
			'icon_selector.select_category_icon' => 'Identify your category',
			'icon_selector.scopes.transport' => 'Transport',
			'icon_selector.scopes.money' => 'Money',
			'icon_selector.scopes.food' => 'Food',
			'icon_selector.scopes.medical' => 'Health',
			'icon_selector.scopes.entertainment' => 'Leisure',
			'icon_selector.scopes.technology' => 'Technology',
			'icon_selector.scopes.other' => 'Others',
			'icon_selector.scopes.logos_financial_institutions' => 'Financial institutions',
			'transaction.display' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Transaction', other: 'Transactions', ), 
			'transaction.select' => 'Select a transaction',
			'transaction.create' => 'New transaction',
			'transaction.new_income' => 'New income',
			'transaction.new_expense' => 'New expense',
			'transaction.new_success' => 'Transaction created successfully',
			'transaction.edit' => 'Edit transaction',
			'transaction.edit_success' => 'Transaction edited successfully',
			'transaction.edit_multiple' => 'Edit transactions',
			'transaction.edit_multiple_success' => ({required Object x}) => '${x} transactions edited successfully',
			'transaction.duplicate' => 'Clone transaction',
			'transaction.duplicate_short' => 'Clone',
			'transaction.duplicate_warning_message' => 'A transaction identical to this will be created with the same date, do you want to continue?',
			'transaction.duplicate_success' => 'Transaction cloned successfully',
			'transaction.delete' => 'Delete transaction',
			'transaction.delete_warning_message' => 'This action is irreversible. The current balance of your accounts and all your statistics will be recalculated',
			'transaction.delete_success' => 'Transaction deleted correctly',
			'transaction.delete_multiple' => 'Delete transactions',
			'transaction.delete_multiple_warning_message' => ({required Object x}) => 'This action is irreversible and will remove ${x} transactions. The current balance of your accounts and all your statistics will be recalculated',
			'transaction.delete_multiple_success' => ({required Object x}) => '${x} transactions deleted correctly',
			'transaction.details' => 'Movement details',
			'transaction.receipt_attached' => 'Receipt attached',
			'transaction.view_receipt' => 'View receipt',
			'transaction.next_payments.accept' => 'Accept',
			'transaction.next_payments.skip' => 'Skip',
			'transaction.next_payments.skip_success' => 'Successfully skipped transaction',
			'transaction.next_payments.skip_dialog_title' => 'Skip transaction',
			'transaction.next_payments.skip_dialog_msg' => ({required Object date}) => 'This action is irreversible. We will move the date of the next move to ${date}',
			'transaction.next_payments.accept_today' => 'Accept today',
			'transaction.next_payments.accept_in_required_date' => ({required Object date}) => 'Accept in required date (${date})',
			'transaction.next_payments.accept_dialog_title' => 'Accept transaction',
			'transaction.next_payments.accept_dialog_msg_single' => 'The new status of the transaction will be null. You can re-edit the status of this transaction whenever you want',
			'transaction.next_payments.accept_dialog_msg' => ({required Object date}) => 'This action will create a new transaction with date ${date}. You will be able to check the details of this transaction on the transaction page',
			'transaction.next_payments.recurrent_rule_finished' => 'The recurring rule has been completed, there are no more payments to make!',
			'transaction.list.all' => 'All transactions',
			'transaction.list.empty' => 'No transactions found to display here. Add a few transactions in the app and maybe you\'ll have better luck next time.',
			'transaction.list.searcher_placeholder' => 'Search by category, description...',
			'transaction.list.searcher_no_results' => 'No transactions found matching the search criteria',
			'transaction.list.loading' => 'Loading more transactions...',
			'transaction.list.selected_short' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} selected', other: '${n} selected', ), 
			'transaction.list.selected_long' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} transaction selected', other: '${n} transactions selected', ), 
			'transaction.list.bulk_edit.dates' => 'Edit dates',
			'transaction.list.bulk_edit.categories' => 'Edit categories',
			'transaction.list.bulk_edit.status' => 'Edit statuses',
			'transaction.filters.title' => 'Transaction filters',
			'transaction.filters.from_value' => 'From amount',
			'transaction.filters.to_value' => 'Up to amount',
			'transaction.filters.from_value_def' => ({required Object x}) => 'From ${x}',
			'transaction.filters.to_value_def' => ({required Object x}) => 'Up to ${x}',
			'transaction.filters.from_date_def' => ({required Object date}) => 'From the ${date}',
			'transaction.filters.to_date_def' => ({required Object date}) => 'Up to the ${date}',
			'transaction.filters.reset' => 'Reset filters',
			'transaction.filters.saved.title' => 'Saved filters',
			'transaction.filters.saved.new_title' => 'New Filter',
			'transaction.filters.saved.edit_title' => 'Edit Filter',
			'transaction.filters.saved.name_label' => 'Filter Name',
			'transaction.filters.saved.name_hint' => 'My custom filter',
			'transaction.filters.saved.save_dialog_title' => 'Save Filter',
			'transaction.filters.saved.save_tooltip' => 'Save current filter',
			'transaction.filters.saved.load_tooltip' => 'Load saved filter',
			'transaction.filters.saved.empty_title' => 'No saved filters found',
			'transaction.filters.saved.empty_description' => 'Save filters here to quickly access them later.',
			'transaction.filters.saved.save_success' => 'Filter saved successfully',
			'transaction.filters.saved.delete_success' => 'Filter deleted successfully',
			'transaction.form.validators.zero' => 'The value of a transaction cannot be equal to zero',
			'transaction.form.validators.date_max' => 'The selected date is after the current one. The transaction will be added as pending',
			'transaction.form.validators.date_after_account_creation' => 'You cannot create a transaction whose date is before the creation date of the account it belongs to',
			'transaction.form.validators.negative_transfer' => 'The monetary value of a transfer cannot be negative',
			'transaction.form.validators.transfer_between_same_accounts' => 'The origin and the destination account cannot be the same',
			'transaction.form.validators.category_required' => 'Select a category before saving',
			'transaction.form.title' => 'Transaction title',
			'transaction.form.title_short' => 'Title',
			'transaction.form.value' => 'Value of the transaction',
			'transaction.form.tap_to_see_more' => 'Tap to see more details',
			'transaction.form.no_tags' => '-- No tags --',
			'transaction.form.description' => 'Description',
			'transaction.form.description_info' => 'Tap here to enter a more detailed description about this transaction',
			'transaction.form.exchange_to_preferred_title' => ({required Object currency}) => 'Exchnage rate to ${currency}',
			'transaction.form.exchange_to_preferred_in_date' => 'On transaction date',
			'transaction.receipt_import.entry_gallery' => 'From receipt (gallery)',
			'transaction.receipt_import.entry_camera' => 'From receipt (camera)',
			'transaction.receipt_import.processing_ocr' => 'Processing OCR...',
			'transaction.receipt_import.processing_ai' => 'Processing AI...',
			'transaction.receipt_import.processing_done' => 'Done',
			'transaction.receipt_import.review_title' => 'Review receipt',
			'transaction.receipt_import.review_subtitle' => 'Validate and edit fields before creating the transaction',
			'transaction.receipt_import.review_cta_continue' => 'Continue',
			'transaction.receipt_import.review_cta_retry' => 'Retry',
			'transaction.receipt_import.error.ocr_empty' => 'No text was detected in the image',
			'transaction.receipt_import.error.ai_failed' => 'AI processing failed, local extraction was used',
			'transaction.receipt_import.error.image_corrupt' => 'The image appears to be corrupted',
			'transaction.receipt_import.error.no_amount' => 'Could not detect an amount',
			'transaction.receipt_import.error.ambiguous_currency' => 'Ambiguous currency, please review it before continuing',
			'transaction.receipt_import.field.amount' => 'Amount',
			'transaction.receipt_import.field.currency' => 'Currency',
			'transaction.receipt_import.field.date' => 'Date',
			'transaction.receipt_import.field.type' => 'Type',
			'transaction.receipt_import.field.counterparty' => 'Counterparty',
			'transaction.receipt_import.field.reference' => 'Reference',
			'transaction.reversed.title' => 'Inverse transaction',
			'transaction.reversed.title_short' => 'Inverse tr.',
			'transaction.reversed.description_for_expenses' => 'Despite being an expense transaction, it has a positive amount. These types of transactions can be used to represent the return of a previously recorded expense, such as a refund or having the payment of a debt.',
			'transaction.reversed.description_for_incomes' => 'Despite being an income transaction, it has a negative amount. These types of transactions can be used to void or correct an income that was incorrectly recorded, to reflect a return or refund of money or to record payment of debts.',
			'transaction.status.display' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Status', other: 'Statuses', ), 
			'transaction.status.display_long' => 'Transaction status',
			'transaction.status.tr_status' => ({required Object status}) => '${status} transaction',
			'transaction.status.none' => 'Stateless',
			'transaction.status.none_descr' => 'Transaction without a specific state',
			'transaction.status.reconciled' => 'Reconciled',
			'transaction.status.reconciled_descr' => 'This transaction has already been validated and corresponds to a real transaction from your bank',
			'transaction.status.unreconciled' => 'Unreconciled',
			'transaction.status.unreconciled_descr' => 'This transaction has not yet been validated and therefore does not yet appear in your real bank accounts. However, it counts for the calculation of balances and statistics in Bolsio',
			'transaction.status.pending' => 'Pending',
			'transaction.status.pending_descr' => 'This transaction is pending and therefore it will not be taken into account when calculating balances and statistics',
			'transaction.status.voided' => 'Voided',
			'transaction.status.voided_descr' => 'Void/cancelled transaction due to payment error or any other reason. It will not be taken into account when calculating balances and statistics',
			'transaction.types.display' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Transaction type', other: 'Transaction types', ), 
			'transaction.types.income' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Income', other: 'Incomes', ), 
			'transaction.types.expense' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Expense', other: 'Expenses', ), 
			'transaction.types.transfer' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Transfer', other: 'Transfers', ), 
			'attachments.view' => 'View attachment',
			'attachments.remove' => 'Remove attachment',
			'attachments.replace' => 'Replace',
			'attachments.upload_from_gallery' => 'Upload from gallery',
			'attachments.upload_from_camera' => 'Take photo',
			'attachments.empty_state' => 'No attachments',
			'bolsio_ai.voice_settings_title' => 'Voice input',
			'bolsio_ai.voice_settings_subtitle' => 'Dictate expenses and ask the assistant',
			'bolsio_ai.voice_permission_title' => 'Microphone access',
			'bolsio_ai.voice_permission_body' => 'Bolsio needs the microphone to transcribe what you dictate and turn it into transactions or questions. Audio is never stored.',
			'bolsio_ai.voice_permission_cta' => 'Got it, continue',
			'bolsio_ai.voice_permission_denied_title' => 'Microphone permission denied',
			'bolsio_ai.voice_permission_denied_body' => 'To dictate or voice-chat, enable the permission in your system settings.',
			'bolsio_ai.voice_permission_denied_snackbar' => 'Microphone permission denied',
			'bolsio_ai.voice_permission_open_settings' => 'Open settings',
			'bolsio_ai.voice_offline_hint' => 'Check your internet connection to use voice dictation.',
			'bolsio_ai.voice_stt_unavailable' => 'Speech recognition isn\'t available on this device.',
			'bolsio_ai.voice_empty_transcript' => 'I didn\'t hear anything, try again.',
			'bolsio_ai.voice_fab_tooltip' => 'Dictate expense',
			'bolsio_ai.voice_listening_title' => 'Listening...',
			'bolsio_ai.voice_listening_subtitle' => 'Tell me the expense in one phrase.',
			'bolsio_ai.voice_listening_hint' => 'E.g. "I spent 20 dollars on lunch"',
			'bolsio_ai.voice_error_title' => 'Something went wrong',
			'bolsio_ai.voice_error_fallback' => 'Recognition error',
			'bolsio_ai.voice_cancel' => 'Cancel',
			'bolsio_ai.voice_done' => 'Done',
			'bolsio_ai.voice_retry' => 'Retry',
			'bolsio_ai.voice_processing' => 'Processing...',
			'bolsio_ai.voice_review_title' => 'New voice transaction',
			'bolsio_ai.voice_review_tap_to_edit' => 'Tap to edit',
			'bolsio_ai.voice_review_account_label' => 'Account',
			'bolsio_ai.voice_review_auto_countdown' => ({required Object seconds}) => 'Auto ${seconds}s',
			'bolsio_ai.voice_review_save' => 'Save',
			'bolsio_ai.voice_review_edit_more' => 'Edit more',
			'bolsio_ai.voice_review_description_placeholder' => 'Description',
			'bolsio_ai.voice_review_amount_placeholder' => 'Amount',
			'bolsio_ai.voice_review_category_placeholder' => 'Category',
			'bolsio_ai.voice_review_category_none' => 'No category',
			'bolsio_ai.voice_review_date_placeholder' => 'Date',
			'bolsio_ai.voice_review_date_today' => 'Today',
			'bolsio_ai.voice_review_account_placeholder' => 'Select account',
			'bolsio_ai.voice_review_description_hint' => 'What was it for...?',
			'bolsio_ai.voice_save_success_auto' => 'Expense saved',
			'bolsio_ai.voice_save_success_manual' => 'Done, saved.',
			'bolsio_ai.voice_save_undo_label' => 'Undo',
			'bolsio_ai.voice_save_undo_success' => 'Deleted',
			'bolsio_ai.voice_validation_amount_zero' => 'Add an amount greater than 0 to continue.',
			'bolsio_ai.voice_validation_account_missing' => 'Select an account.',
			'bolsio_ai.voice_validation_category_missing' => 'Select a category.',
			'bolsio_ai.voice_flow_no_proposal' => 'I couldn\'t extract an expense from what you said.',
			'bolsio_ai.voice_flow_error_title' => 'I couldn\'t interpret that',
			'bolsio_ai.voice_flow_gateway_unavailable_title' => 'AI service unavailable',
			'bolsio_ai.voice_flow_gateway_unavailable' => 'The AI service is not available. Please try again in a moment.',
			'bolsio_ai.chat_input_hint_default' => 'Ask about your finances...',
			'bolsio_ai.chat_input_hint_using_tools' => 'Looking up your data...',
			'bolsio_ai.chat_error_generic' => 'I couldn\'t process your question, try again.',
			'bolsio_ai.chat_error_loop_cap' => 'I couldn\'t complete the query.',
			'bolsio_ai.chat_tool_create_transaction_expense' => 'Create expense',
			'bolsio_ai.chat_tool_create_transaction_income' => 'Register income',
			'bolsio_ai.chat_tool_create_transfer' => 'Create transfer',
			'bolsio_ai.chat_tool_generic_confirm' => 'Confirm action',
			'bolsio_ai.chat_tool_review_subtitle' => 'Check the details before confirming.',
			'bolsio_ai.chat_tool_no_details' => 'No details available.',
			'bolsio_ai.chat_tool_cta_approve' => 'Approve and run',
			'bolsio_ai.chat_tool_cta_cancel' => 'Cancel',
			'bolsio_ai.chat_tool_field_amount' => 'Amount',
			'bolsio_ai.chat_tool_field_type' => 'Type',
			'bolsio_ai.chat_tool_field_type_income' => 'Income',
			'bolsio_ai.chat_tool_field_type_expense' => 'Expense',
			'bolsio_ai.chat_tool_field_description' => 'Description',
			'bolsio_ai.chat_tool_field_category' => 'Category',
			'bolsio_ai.chat_tool_field_account' => 'Account',
			'bolsio_ai.chat_tool_field_date' => 'Date',
			'bolsio_ai.chat_tool_field_from_account' => 'From',
			'bolsio_ai.chat_tool_field_to_account' => 'To',
			'bolsio_ai.chat_tool_field_value_in_destiny' => 'Destination amount',
			'bolsio_ai.chat_header' => 'Bolsi',
			'bolsio_ai.chat_boot_loading' => 'Loading financial context...',
			'bolsio_ai.chat_disabled' => 'AI chat is disabled in settings.',
			'bolsio_ai.chat_welcome_message' => 'Hi! I\'m Bolsi 👛 your pocket buddy. How can I help today?',
			'transfer.display' => 'Transfer',
			'transfer.transfers' => 'Transfers',
			'transfer.transfer_to' => ({required Object account}) => 'Transfer to ${account}',
			'transfer.create' => 'New Transfer',
			'transfer.need_two_accounts_warning_header' => 'Ops!',
			'transfer.need_two_accounts_warning_message' => 'At least two accounts are needed to perform this action. If you need to adjust or edit the current balance of this account, click the edit button',
			'transfer.form.from' => 'Origin account',
			'transfer.form.to' => 'Destination account',
			'transfer.form.value_in_destiny.title' => 'Amount transferred at destination',
			'transfer.form.value_in_destiny.amount_short' => ({required Object amount}) => '${amount} to target account',
			'recurrent_transactions.title' => 'Recurrent transactions',
			'recurrent_transactions.title_short' => 'Rec. transactions',
			'recurrent_transactions.empty' => 'It looks like you don\'t have any recurring transactions. Create a monthly, yearly, or weekly recurring transaction and it will appear here',
			'recurrent_transactions.total_expense_title' => 'Total expense per period',
			'recurrent_transactions.total_expense_descr' => '* Without considering the start and end date of each recurrence',
			'recurrent_transactions.details.title' => 'Recurrent transaction',
			'recurrent_transactions.details.descr' => 'The next moves for this transaction are shown below. You can accept the first move or skip this move',
			'recurrent_transactions.details.last_payment_info' => 'This movement is the last of the recurring rule, so this rule will be automatically deleted when confirming this action',
			'recurrent_transactions.details.delete_header' => 'Delete recurring transaction',
			'recurrent_transactions.details.delete_message' => 'This action is irreversible and will not affect transactions you have already confirmed/paid for',
			'recurrent_transactions.status.delayed_by' => ({required Object x}) => 'Delayed by ${x}d',
			'recurrent_transactions.status.coming_in' => ({required Object x}) => 'In ${x} days',
			'account.details' => 'Account details',
			'account.date' => 'Opening date',
			'account.close_date' => 'Closing date',
			'account.reopen' => 'Re-open account',
			'account.reopen_short' => 'Re-open',
			'account.reopen_descr' => 'Are you sure you want to reopen this account?',
			'account.balance' => 'Account balance',
			'account.n_transactions' => 'Number of transactions',
			'account.add_money' => 'Add money',
			'account.withdraw_money' => 'Withdraw money',
			'account.no_accounts' => 'No accounts found to display here. Add an account by clicking the \'+\' button at the bottom',
			'account.types.title' => 'Account type',
			'account.types.warning' => 'Once the type of account has been chosen, it cannot be changed in the future',
			'account.types.normal' => 'Normal account',
			'account.types.normal_descr' => 'Useful to record your day-to-day finances. It is the most common account, it allows you to add expenses, income...',
			'account.types.saving' => 'Savings account',
			'account.types.saving_descr' => 'You will only be able to add and withdraw money from it from other accounts. Perfect to start saving money',
			'account.form.name' => 'Account name',
			'account.form.name_placeholder' => 'Ex: Savings account',
			_ => null,
		} ?? switch (path) {
			'account.form.notes' => 'Notes',
			'account.form.notes_placeholder' => 'Type some notes/description about this account',
			'account.form.initial_balance' => 'Initial balance',
			'account.form.current_balance' => 'Current balance',
			'account.form.create' => 'Create account',
			'account.form.edit' => 'Edit account',
			'account.form.currency_not_found_warn' => 'You do not have information on exchange rates for this currency. 1.0 will be used as the default exchange rate. You can modify this in the settings',
			'account.form.already_exists' => 'There is already another one with the same name, please write another',
			'account.form.tr_before_opening_date' => 'There are transactions in this account with a date before the opening date',
			'account.form.iban' => 'IBAN',
			'account.form.swift' => 'SWIFT',
			'account.form.tracked_since' => 'Track since',
			'account.form.tracked_since_hint' => 'Optional',
			'account.form.tracked_since_info' => 'Transactions before this date will appear in history but will not affect balance.',
			'account.form.tracked_since_validation_after_closing' => 'Track-since date cannot be later than the account closing date.',
			'account.badge.pre_tracking' => 'Historical',
			'account.badge.pre_tracking_tooltip' => 'Does not affect current balance',
			'account.retroactive.preview_title' => 'Balance impact',
			'account.retroactive.preview_message' => ({required Object current, required Object simulated}) => 'Current balance: ${current} → New balance: ${simulated}',
			'account.retroactive.strong_confirm_hint' => 'Type CONFIRM to proceed',
			'account.retroactive.strong_confirm_mismatch' => 'Text does not match. Change canceled.',
			'account.retroactive.accept' => 'Accept',
			'account.retroactive.cancel' => 'Cancel',
			'account.delete.warning_header' => 'Delete account?',
			'account.delete.warning_text' => 'This action will delete this account and all its transactions',
			'account.delete.success' => 'Account deleted successfully',
			'account.close.title' => 'Close account',
			'account.close.title_short' => 'Close',
			'account.close.warn' => 'This account will no longer appear in certain listings and you will not be able to create transactions in it with a date later than the one specified below. This action does not affect any transactions or balance, and you can also reopen this account at any time. ',
			'account.close.should_have_zero_balance' => 'You must have a current balance of 0 in this account to close it. Please edit the account before continuing',
			'account.close.should_have_no_transactions' => 'This account has transactions after the specified close date. Delete them or edit the account close date before continuing',
			'account.close.success' => 'Account closed successfully',
			'account.close.unarchive_succes' => 'Account successfully re-opened',
			'account.select.one' => 'Select an account',
			'account.select.all' => 'All accounts',
			'account.select.multiple' => 'Select accounts',
			'currencies.currency_converter' => 'Currency converter',
			'currencies.currency' => 'Currency',
			'currencies.currency_settings' => 'Currency settings',
			'currencies.currency_manager' => 'Currency manager',
			'currencies.currency_manager_descr' => 'Configure your currency and its exchange rates with others',
			'currencies.preferred_currency' => 'Preferred/base currency',
			'currencies.tap_to_change_preferred_currency' => 'Tap to change',
			'currencies.change_preferred_currency_title' => 'Change preferred currency',
			'currencies.change_preferred_currency_msg' => 'All stats and budgets will be displayed in this currency from now on. Accounts and transactions will keep the currency they had. All saved exchange rates will be deleted if you execute this action. Do you wish to continue?',
			'currencies.exchange_rate_form.equal_to_preferred_warn' => 'The currency cannot be equal to the user currency',
			'currencies.exchange_rate_form.override_existing_warn' => 'An exchange rate for this currency in this date already exists. If you continue, the previous one will be overwritten',
			'currencies.exchange_rate_form.specify_a_currency' => 'Please specify a currency',
			'currencies.exchange_rate_form.add' => 'Add exchange rate',
			'currencies.exchange_rate_form.add_success' => 'Exchange rate added successfully',
			'currencies.exchange_rate_form.edit' => 'Edit exchange rate',
			'currencies.exchange_rate_form.edit_success' => 'Exchange rate edited successfully',
			'currencies.exchange_rate_form.remove_all' => 'Delete all exchange rates',
			'currencies.exchange_rate_form.remove_all_warning' => 'This action is irreversible and will delete all exchange rates for this currency',
			'currencies.types.display' => 'Currency type',
			'currencies.types.fiat' => 'FIAT',
			'currencies.types.crypto' => 'Cryptocurrency',
			'currencies.types.other' => 'Other',
			'currencies.currency_form.name' => 'Display Name',
			'currencies.currency_form.code' => 'Currency Code',
			'currencies.currency_form.symbol' => 'Symbol',
			'currencies.currency_form.decimal_digits' => 'Decimal Digits',
			'currencies.currency_form.create' => 'Create currency',
			'currencies.currency_form.create_success' => 'Currency created successfully',
			'currencies.currency_form.edit' => 'Edit currency',
			'currencies.currency_form.edit_success' => 'Currency edited successfully',
			'currencies.currency_form.delete' => 'Delete currency',
			'currencies.currency_form.delete_success' => 'Currency deleted successfully',
			'currencies.currency_form.already_exists' => 'A currency with this code already exists. You may want to edit it',
			'currencies.delete_all_success' => 'Deleted exchange rates successfully',
			'currencies.historical' => 'Historical rates',
			'currencies.historical_empty' => 'No historical exchange rates found for this currency',
			'currencies.exchange_rate' => 'Exchange rate',
			'currencies.exchange_rates' => 'Exchange rates',
			'currencies.min_exchange_rate' => 'Minimum exchange rate',
			'currencies.max_exchange_rate' => 'Maximum exchange rate',
			'currencies.empty' => 'Add exchange rates here so that if you have accounts in currencies other than your base currency our charts are more accurate',
			'currencies.select_a_currency' => 'Select a currency',
			'currencies.search' => 'Search by name or by currency code',
			'tags.display' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Label', other: 'Tags', ), 
			'tags.form.name' => 'Tag name',
			'tags.form.description' => 'Description',
			'tags.select.title' => 'Select tags',
			'tags.select.all' => 'All the tags',
			'tags.empty_list' => 'You haven\'t created any tags yet. Tags and categories are a great way to categorize your movements',
			'tags.without_tags' => 'Without tags',
			'tags.add' => 'Add tag',
			'tags.create' => 'Create label',
			'tags.create_success' => 'Label created successfully',
			'tags.already_exists' => 'This tag name already exists. You may want to edit it',
			'tags.edit' => 'Edit tag',
			'tags.edit_success' => 'Tag edited successfully',
			'tags.delete_success' => 'Category deleted successfully',
			'tags.delete_warning_header' => 'Delete tag?',
			'tags.delete_warning_message' => 'This action will not delete transactions that have this tag.',
			'categories.unknown' => 'Unknown category',
			'categories.create' => 'Create category',
			'categories.create_success' => 'Category created correctly',
			'categories.new_category' => 'New category',
			'categories.already_exists' => 'The name of this category already exists. Maybe you want to edit it',
			'categories.edit' => 'Edit category',
			'categories.edit_success' => 'Category edited correctly',
			'categories.name' => 'Category name',
			'categories.type' => 'Category type',
			'categories.both_types' => 'Both types',
			'categories.subcategories' => 'Subcategories',
			'categories.subcategories_add' => 'Add subcategory',
			'categories.make_parent' => 'Make to category',
			'categories.make_child' => 'Make a subcategory',
			'categories.make_child_warning1' => ({required Object destiny}) => 'This category and its subcategories will become subcategories of <b>${destiny}</b>.',
			'categories.make_child_warning2' => ({required Object x, required Object destiny}) => 'Their transactions <b>(${x})</b> will be moved to the new subcategories created within the <b>${destiny}</b> category.',
			'categories.make_child_success' => 'Subcategories created successfully',
			'categories.merge' => 'Merge with another category',
			'categories.merge_warning1' => ({required Object x, required Object from, required Object destiny}) => 'All transactions (${x}) associated with the category <b>${from}</b> will be moved to the category <b>${destiny}</b>',
			'categories.merge_warning2' => ({required Object from}) => 'The category <b>${from}</b> will be irreversibly deleted.',
			'categories.merge_success' => 'Category merged successfully',
			'categories.delete_success' => 'Category deleted correctly',
			'categories.delete_warning_header' => 'Delete category?',
			'categories.delete_warning_message' => ({required Object x}) => 'This action will irreversibly delete all transactions <b>(${x})</b> related to this category.',
			'categories.select.title' => 'Select categories',
			'categories.select.select_one' => 'Select a category',
			'categories.select.select_subcategory' => 'Choose a subcategory',
			'categories.select.without_subcategory' => 'Without subcategory',
			'categories.select.all' => 'All categories',
			'categories.select.all_short' => 'All',
			'budgets.title' => 'Budgets',
			'budgets.status' => 'Budget status',
			'budgets.repeated' => 'Recurring',
			'budgets.one_time' => 'Once',
			'budgets.actives' => 'Actives',
			'budgets.from_budgeted' => 'left of ',
			'budgets.days_left' => 'days left',
			'budgets.days_to_start' => 'days to start',
			'budgets.since_expiration' => 'days since expiration',
			'budgets.no_budgets' => 'There seem to be no budgets to display in this section. Start by creating a budget by clicking the button below',
			'budgets.delete' => 'Delete budget',
			'budgets.delete_warning' => 'This action is irreversible. Categories and transactions referring to this quote will not be deleted',
			'budgets.form.title' => 'Add a budget',
			'budgets.form.name' => 'Budget name',
			'budgets.form.value' => 'Limit quantity',
			'budgets.form.create' => 'Add budget',
			'budgets.form.create_success' => 'Budget created successfully',
			'budgets.form.edit' => 'Edit budget',
			'budgets.form.edit_success' => 'Budget edited successfully',
			'budgets.form.negative_warn' => 'The budgets can not have a negative amount',
			'budgets.details.title' => 'Budget Details',
			'budgets.details.statistics' => 'Statistics',
			'budgets.details.budget_value' => 'Budgeted',
			'budgets.details.expend_evolution' => 'Expenditure evolution',
			'budgets.details.no_transactions' => 'It seems that you have not made any expenses related to this budget',
			'budgets.target_timeline_statuses.active' => 'Active budget',
			'budgets.target_timeline_statuses.past' => 'Finished budget',
			'budgets.target_timeline_statuses.future' => 'Future budget',
			'budgets.progress.labels.active_on_track' => 'On track',
			'budgets.progress.labels.active_overspending' => 'Overspending',
			'budgets.progress.labels.active_indeterminate' => 'Active',
			'budgets.progress.labels.success' => 'Achieved',
			'budgets.progress.labels.fail' => 'Budget exceeded',
			'budgets.progress.description.active_on_track' => ({required Object dailyAmount, required Object remainingDays}) => 'You can spend ${dailyAmount} per day for the remaining ${remainingDays} days',
			'budgets.progress.description.active_overspending' => ({required Object dailyAmount, required Object remainingDays}) => 'To get back on track, you should limit your spending to ${dailyAmount} per day for the remaining ${remainingDays} days',
			'budgets.progress.description.active_indeterminate' => ({required Object amount}) => 'You have ${amount} left to spend.',
			'budgets.progress.description.active_exceeded' => ({required Object amount}) => 'You have already exceeded your budget limit by ${amount}. If you don\'t find any incomes for this budget, you should stop spending for the rest of its period',
			'budgets.progress.description.success' => 'Great job! This budget has already finish successfully. Keep creating budgets to manage your expenses',
			'budgets.progress.description.fail' => ({required Object amount}) => 'You exceeded the budget by ${amount}. Try to be more careful next time!',
			'goals.title' => 'Goals',
			'goals.status' => 'Goal status',
			'goals.type.display' => 'Goal Type',
			'goals.type.income.title' => 'Savings Goal',
			'goals.type.income.descr' => 'Ideal for saving money. You succeed when the balance goes above your target.',
			'goals.type.expense.title' => 'Spending Goal',
			'goals.type.expense.descr' => 'Track how much you spend and aim to reach a target amount. Works good for donations, charity, leisure spending...',
			'goals.empty_title' => 'No goals found',
			'goals.empty_description' => 'Create a new goal to start tracking your savings!',
			'goals.delete' => 'Delete goal',
			'goals.delete_warning' => 'This action is irreversible. Categories and transactions referring to this goal will not be deleted',
			'goals.form.new_title' => 'New Goal',
			'goals.form.edit_title' => 'Edit Goal',
			'goals.form.target_amount' => 'Target Amount',
			'goals.form.initial_amount' => 'Initial Amount',
			'goals.form.name' => 'Name',
			'goals.form.name_hint' => 'My Saving Goal',
			'goals.form.create_success' => 'Goal created successfully',
			'goals.form.edit_success' => 'Goal edited successfully',
			'goals.form.negative_warn' => 'The goal amount cannot be negative',
			'goals.details.title' => 'Goal Details',
			'goals.details.statistics' => 'Statistics',
			'goals.details.goal_value' => 'Goal Target',
			'goals.details.evolution' => 'Evolution',
			'goals.details.no_transactions' => 'It seems that you have not made any transactions related to this goal',
			'goals.target_timeline_statuses.active' => 'Active goal',
			'goals.target_timeline_statuses.past' => 'Finished goal',
			'goals.target_timeline_statuses.future' => 'Future goal',
			'goals.progress.labels.active_on_track' => 'On track',
			'goals.progress.labels.active_behind_schedule' => 'Behind schedule',
			'goals.progress.labels.active_indeterminate' => 'Active',
			'goals.progress.labels.success' => 'Goal reached',
			'goals.progress.labels.fail' => 'Goal failed',
			'goals.progress.description.active_on_track' => ({required Object dailyAmount, required Object remainingDays}) => 'You are on track to seek your goal! You have to save ${dailyAmount} per day for the remaining ${remainingDays} days',
			'goals.progress.description.active_behind_schedule' => ({required Object dailyAmount, required Object remainingDays}) => 'You are behind schedule. You have to save ${dailyAmount} per day to reach your goal in ${remainingDays} days',
			'goals.progress.description.active_indeterminate' => ({required Object amount}) => 'You need ${amount} more to reach your goal.',
			'goals.progress.description.success' => 'Congratulations! You reached your goal.',
			'goals.progress.description.fail' => ({required Object amount}) => 'You missed your goal by ${amount}.',
			'debts.display' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Debt', other: 'Debts', ), 
			'debts.form.name' => 'Debt name',
			'debts.form.initial_amount' => 'Initial amount',
			'debts.form.total_amount' => 'Total amount',
			'debts.form.step_initial_value' => 'Initial value',
			'debts.form.step_details' => 'Details',
			'debts.form.from_transaction.title' => 'From a transaction',
			'debts.form.from_transaction.tap_to_select' => 'Tap to select a transaction',
			'debts.form.from_amount.title' => 'From an initial amount',
			'debts.form.from_amount.description' => 'This amount will not be taken into account for statistics as an expense/income. It will be used to calculate balances and net worth',
			'debts.direction.lent' => 'Lent',
			'debts.direction.borrowed' => 'Borrowed',
			'debts.status.active' => 'Active',
			'debts.status.close' => 'Closed',
			'debts.details.collected_amount' => 'Collected amount',
			'debts.details.remaining' => 'Remaining',
			'debts.details.no_deadline' => 'No deadline',
			'debts.details.in_days' => ({required Object x}) => 'In ${x} days',
			'debts.details.due_today' => 'Due today',
			'debts.details.days_ago' => ({required Object x}) => '${x} days ago',
			'debts.details.overdue_by' => ({required Object x}) => 'Overdue by ${x} days',
			'debts.details.per_day' => '/ day',
			'debts.details.no_transactions' => 'No transactions found for this debt',
			'debts.empty.no_debts_active' => 'No active debts found. Start by creating a new debt by clicking the button below',
			'debts.empty.no_debts_closed' => 'No closed debts found. A debt is closed when you have collected all the money from it or you have paid all the money you owed.',
			'debts.actions.edit.title' => 'Edit debt',
			'debts.actions.edit.success' => 'Debt edited successfully',
			'debts.actions.delete.warning_header' => 'Delete this debt?',
			'debts.actions.delete.warning_text' => 'This action cannot be undone. Linked transactions will not be deleted but will no longer be associated with this debt.',
			'debts.actions.add_register.title' => 'Add movement',
			'debts.actions.add_register.success' => 'Movement added successfully',
			'debts.actions.add_register.fab_label' => 'Add register',
			'debts.actions.add_register.modal_title' => 'Add register to this debt',
			'debts.actions.add_register.modal_subtitle' => 'Choose one of the following options to link a transaction to this debt',
			'debts.actions.link_transaction.title' => 'Link existing transaction',
			'debts.actions.link_transaction.description' => 'Choose an existing record to link it to this debt',
			'debts.actions.link_transaction.success' => 'Transaction linked to debt',
			'debts.actions.link_transaction.creating' => ({required Object name}) => 'You are creating a transaction linked to the debt <b>${name}</b>',
			'debts.actions.unlink_transaction.title' => 'Unlink from debt',
			'debts.actions.unlink_transaction.warning_text' => 'This transaction will no longer be associated with this debt.',
			'debts.actions.unlink_transaction.success' => 'Transaction unlinked from debt',
			'debts.actions.new_transaction.title' => 'Add new transaction',
			'debts.actions.new_transaction.description' => 'Manually add or reduce the debt by creating a new transaction linked to this debt',
			'debts.actions.create.title' => 'Create debt',
			'debts.actions.create.success' => 'Debt created successfully',
			'target_timeline_statuses.active' => 'Active',
			'target_timeline_statuses.past' => 'Finished',
			'target_timeline_statuses.future' => 'Future',
			'backup.no_file_selected' => 'No file selected',
			'backup.no_directory_selected' => 'No directory selected',
			'backup.export.title' => 'Export your data',
			'backup.export.title_short' => 'Export',
			'backup.export.type_of_export' => 'Type of export',
			'backup.export.other_options' => 'Options',
			'backup.export.all' => 'Full backup',
			'backup.export.all_descr' => 'Export all your data (accounts, transactions, budgets, settings...). Import them again at any time so you don\'t lose anything.',
			'backup.export.transactions' => 'Transactions backup',
			'backup.export.transactions_descr' => 'Export your transactions in CSV so you can more easily analyze them in other programs or applications.',
			'backup.export.transactions_to_export' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '1 transaction to export', other: '${n} transactions to export', ), 
			'backup.export.description' => 'Download your data in different formats',
			'backup.export.send_file' => 'Send file',
			'backup.export.see_folder' => 'See folder',
			'backup.export.success' => ({required Object x}) => 'File saved successfully in ${x}',
			'backup.export.error' => 'Error downloading the file. Please contact the developer via lozin.technologies@gmail.com',
			'backup.export.dialog_title' => 'Save/Send file',
			'backup.import.title' => 'Import your data',
			'backup.import.title_short' => 'Import',
			'backup.import.restore_backup' => 'Restore Backup',
			'backup.import.restore_backup_descr' => 'Import a previously saved database from Bolsio. This action will replace any current application data with the new data',
			'backup.import.restore_backup_warn_description' => 'When importing a new database, you will lose all data currently saved in the app. It is recommended to make a backup before continuing. Do not upload here any file whose origin you do not know, upload only files that you have previously downloaded from Bolsio',
			'backup.import.restore_backup_warn_title' => 'Overwrite all data',
			'backup.import.select_other_file' => 'Select other file',
			'backup.import.tap_to_select_file' => 'Tap to select a file',
			'backup.import.manual_import.title' => 'Manual import',
			'backup.import.manual_import.descr' => 'Import transactions from a .csv file manually',
			'backup.import.manual_import.default_account' => 'Default account',
			'backup.import.manual_import.remove_default_account' => 'Remove default account',
			'backup.import.manual_import.default_category' => 'Default Category',
			'backup.import.manual_import.select_a_column' => 'Select a column from the .csv',
			'backup.import.manual_import.steps.0' => 'Select your file',
			'backup.import.manual_import.steps.1' => 'Column for quantity',
			'backup.import.manual_import.steps.2' => 'Column for account',
			'backup.import.manual_import.steps.3' => 'Column for category',
			'backup.import.manual_import.steps.4' => 'Column for date',
			'backup.import.manual_import.steps.5' => 'other columns',
			'backup.import.manual_import.steps_descr.0' => 'Select a .csv file from your device. Make sure it has a first row that describes the name of each column',
			'backup.import.manual_import.steps_descr.1' => 'Select the column where the value of each transaction is specified. Use negative values for expenses and positive values for income.',
			'backup.import.manual_import.steps_descr.2' => 'Select the column where the account to which each transaction belongs is specified. You can also select a default account in case we cannot find the account you want. If a default account is not specified, we will create one with the same name ',
			'backup.import.manual_import.steps_descr.3' => 'Specify the column where the transaction category name is located. You must specify a default category so that we assign this category to transactions, in case the category cannot be found',
			'backup.import.manual_import.steps_descr.4' => 'Select the column where the date of each transaction is specified. If not specified, transactions will be created with the current date',
			'backup.import.manual_import.steps_descr.5' => 'Specifies the columns for other optional transaction attributes',
			'backup.import.manual_import.success' => ({required Object x}) => 'Successfully imported ${x} transactions',
			'backup.import.success' => 'Import performed successfully',
			'backup.import.error' => 'Error importing file. Please contact developer via lozin.technologies@gmail.com',
			'backup.import.cancelled' => 'Import was cancelled by the user',
			'backup.about.title' => 'Information about your database',
			'backup.about.create_date' => 'Creation date',
			'backup.about.modify_date' => 'Last modified',
			'backup.about.last_backup' => 'Last backup',
			'backup.about.size' => 'Size',
			'profile.your_avatar' => 'Your avatar',
			'profile.upload_photo' => 'Upload photo',
			'profile.replace_photo' => 'Replace',
			'profile.your_photo_badge' => 'Your photo',
			'profile.name_label' => 'Your visible name',
			'profile.options_count' => ({required Object count}) => '${count} options',
			'settings.title_long' => 'Settings & Customization',
			'settings.title_short' => 'Settings',
			'settings.description' => 'Theme, Language, Data and more',
			'settings.edit_profile' => 'Edit profile',
			'settings.general.menu_title' => 'General Settings',
			'settings.general.menu_descr' => 'Language, privacy, and more',
			'settings.general.show_all_decimals' => 'Show all decimal places',
			'settings.general.show_all_decimals_descr' => 'Whether to show all decimals places even if there are trailing zeros',
			'settings.general.language.section' => 'Language and texts',
			'settings.general.language.title' => 'App language',
			'settings.general.language.descr' => 'Language in which the texts will be displayed in the app',
			'settings.general.language.help' => 'If you want to collaborate with the translations of this app, you can consult <a href=\'__BOLSIO_GITHUB_URL__/tree/main/lib/i18n\'>our guide</a>',
			'settings.general.locale.title' => 'Region',
			'settings.general.locale.auto' => 'System',
			'settings.general.locale.descr' => 'Set the format to use for dates, numbers...',
			'settings.general.locale.warn' => 'When changing region the app will update',
			'settings.general.locale.first_day_of_week' => 'First day of week',
			'settings.security.title' => 'Security',
			'settings.security.private_mode_at_launch' => 'Private mode at launch',
			'settings.security.private_mode_at_launch_descr' => 'Launch the app in private mode by default',
			'settings.security.private_mode' => 'Private mode',
			'settings.security.private_mode_descr' => 'Hide all monetary values',
			'settings.security.private_mode_activated' => 'Private mode activated',
			'settings.security.private_mode_deactivated' => 'Private mode disabled',
			'settings.security.biometric.title' => 'Use fingerprint/biometrics',
			'settings.security.biometric.descr' => 'Require authentication when opening the app',
			'settings.security.biometric.section_title' => 'Biometric lock',
			'settings.hidden_mode.title' => 'Hidden Mode',
			'settings.hidden_mode.menu_descr' => 'Hide your savings accounts behind a PIN',
			'settings.hidden_mode.enable' => 'Enable Hidden Mode',
			'settings.hidden_mode.description' => 'When active, your savings accounts and their transactions are hidden from balances, charts and lists. To see the real balance: 6 taps on your profile picture + PIN.',
			'settings.hidden_mode.change_pin' => 'Change PIN',
			'settings.hidden_mode.change_pin_descr' => 'Replace your current PIN with a new one',
			'settings.hidden_mode.enabled_badge' => 'Active',
			'settings.hidden_mode.pin.setup_title' => 'Create your PIN',
			'settings.hidden_mode.pin.setup_subtitle' => 'This PIN will unlock your hidden accounts',
			'settings.hidden_mode.pin.confirm_title' => 'Confirm your PIN',
			'settings.hidden_mode.pin.unlock_title' => 'Enter your PIN',
			'settings.hidden_mode.pin.change_old_title' => 'Enter your current PIN',
			'settings.hidden_mode.pin.change_new_title' => 'Create a new PIN',
			'settings.hidden_mode.pin.change_confirm_title' => 'Confirm the new PIN',
			'settings.hidden_mode.pin.disable_title' => 'Confirm your PIN to disable Hidden Mode',
			'settings.hidden_mode.pin.mismatch' => 'PINs do not match',
			'settings.hidden_mode.pin.incorrect' => 'Incorrect PIN',
			'settings.hidden_mode.pin.too_many_attempts' => ({required Object seconds}) => 'Too many attempts. Try again in ${seconds}s',
			'settings.hidden_mode.pin.use_biometric' => 'Use fingerprint',
			'settings.hidden_mode.pin.biometric_reason' => 'Unlock Bolsio',
			'settings.hidden_mode.pin.pin_changed' => 'PIN updated',
			'settings.hidden_mode.pin.unlocked' => 'Full view unlocked',
			'settings.transactions.menu_title' => 'Transactions',
			'settings.transactions.menu_descr' => 'Configure the behavior of your transactions',
			'settings.transactions.title' => 'Transactions Settings',
			'settings.transactions.style.title' => 'Transaction style',
			'settings.transactions.style.subtitle' => 'Configure how transactions look in the different lists of the app',
			'settings.transactions.style.show_tags' => 'Show Tags',
			'settings.transactions.style.show_time' => 'Show Time',
			'settings.transactions.swipe_actions.title' => 'Swipe actions',
			'settings.transactions.swipe_actions.choose_description' => 'Choose what action will be triggered when you swipe a transaction item in the list using this swipe direction',
			'settings.transactions.swipe_actions.swipe_left' => 'Swipe left',
			'settings.transactions.swipe_actions.swipe_right' => 'Swipe right',
			'settings.transactions.swipe_actions.none' => 'No action',
			'settings.transactions.swipe_actions.toggle_reconciled' => 'Toggle reconciled',
			'settings.transactions.swipe_actions.toggle_pending' => 'Toggle pending',
			'settings.transactions.swipe_actions.toggle_voided' => 'Toggle voided',
			'settings.transactions.swipe_actions.toggle_unreconciled' => 'Toggle unreconciled',
			'settings.transactions.swipe_actions.remove_status' => 'Remove status',
			'settings.transactions.default_values.title' => 'Default Form Values',
			'settings.transactions.default_values.page_title' => 'New Transaction: Default Form Values',
			'settings.transactions.default_values.reuse_last_transaction' => 'Reuse Last Transaction Values',
			'settings.transactions.default_values.reuse_last_transaction_descr' => 'Automatically fill the form with some values from the last created transaction',
			'settings.transactions.default_values.fields_to_reuse' => 'Fields to reuse',
			'settings.transactions.default_values.reuse_last_values_modal_descr' => 'Select the fields that should be pre-filled with the values from the last created transaction.',
			'settings.transactions.default_values.default_values_separator' => 'Default Values',
			'settings.transactions.default_values.default_category' => 'Default Category',
			'settings.transactions.default_values.default_status' => 'Default Status',
			'settings.transactions.default_values.default_tags' => 'Default Tags',
			'settings.transactions.default_values.no_tags_selected' => 'No tags selected',
			'settings.transactions.default_type.title' => 'Default Type',
			'settings.transactions.default_type.modal_title' => 'Select Default Type',
			'settings.auto_import.menu_title' => 'Bank auto-import',
			'settings.appearance.menu_title' => 'Theme & Style',
			'settings.appearance.menu_descr' => 'Theme selection, colors and other things related to the app appearance',
			'settings.appearance.theme_and_colors' => 'Theme and colors',
			'settings.appearance.theme.title' => 'Theme',
			'settings.appearance.theme.auto' => 'System',
			'settings.appearance.theme.light' => 'Light',
			'settings.appearance.theme.dark' => 'Dark',
			'settings.appearance.amoled_mode' => 'AMOLED mode',
			'settings.appearance.amoled_mode_descr' => 'Use a pure black wallpaper when possible. This will slightly help the battery of devices with AMOLED screens',
			'settings.appearance.dynamic_colors' => 'Dynamic colors',
			'settings.appearance.dynamic_colors_descr' => 'Use your system accent color whenever possible',
			'settings.appearance.accent_color' => 'Accent color',
			'settings.appearance.accent_color_descr' => 'Choose the color the app will use to emphasize certain parts of the interface',
			'settings.appearance.text' => 'Text',
			'settings.appearance.font' => 'Font',
			'settings.appearance.font_platform' => 'Platform',
			'statement_import.title' => 'Import account statement',
			'statement_import.subtitle' => 'We will process the movements with AI',
			'statement_import.ai_badge' => 'Private AI · your infrastructure',
			'statement_import.capture.cta_camera' => 'Take a photo',
			'statement_import.capture.cta_file' => 'Upload PDF or image',
			'statement_import.capture.pdf_warning_title' => 'Multi-page PDF',
			'statement_import.capture.pdf_warning_body' => ({required Object pages}) => 'This PDF has ${pages} pages. We will only process page 1.',
			'statement_import.capture.pdf_warning_continue' => 'Continue',
			'statement_import.capture.date_picker_title' => 'When did you take the capture?',
			'statement_import.capture.error_read' => 'Could not read the image',
			'statement_import.processing.title' => 'Reading account statement…',
			'statement_import.processing.analyzing' => 'Analyzing…',
			'statement_import.processing.found' => ({required Object n}) => '${n} found',
			'statement_import.processing.cancel' => 'Cancel',
			'statement_import.processing.error_timeout' => 'Could not read in time. Try again',
			'statement_import.processing.error_generic' => 'Could not read. Try again',
			'statement_import.processing.retry' => 'Retry',
			'statement_import.processing.back' => 'Back',
			'statement_import.review.title' => 'Review movements',
			'statement_import.review.empty' => 'No movements detected',
			'statement_import.review.toggle_all' => 'All',
			'statement_import.review.toggle_none' => 'None',
			'statement_import.review.continue_cta' => ({required Object n}) => 'Continue · ${n} movements',
			'statement_import.review.and_label' => ({required Object n}) => 'AND · only rows meeting ${n} criteria',
			'statement_import.review.clear' => 'Clear',
			'statement_import.review.informative_warning' => 'Some rows have a date after Fresh Start. They will be included in the history but will not affect the balance.',
			'statement_import.review.fresh_start_dialog_title' => 'Configure Fresh Start first',
			'statement_import.review.fresh_start_dialog_body' => 'To import informative movements (history) you need to configure the date from which you track this account.',
			'statement_import.review.fresh_start_configure' => 'Configure now',
			'statement_import.review.tag_exists' => 'Already exists',
			'statement_import.review.tag_fee' => 'Fee',
			'statement_import.review.tag_prefresh' => 'Pre-Fresh',
			'statement_import.modes.missing' => 'Missing',
			'statement_import.modes.income' => 'Income',
			'statement_import.modes.expense' => 'Expenses',
			'statement_import.modes.fees' => 'Fees',
			'statement_import.modes.informative' => 'Informative',
			'statement_import.confirm.title' => 'Confirm import',
			'statement_import.confirm.movements' => ({required Object n}) => '${n} movements',
			'statement_import.confirm.informative_chip' => 'History · does not affect balance',
			'statement_import.confirm.breakdown_title' => 'Breakdown',
			'statement_import.confirm.breakdown_income' => 'Income',
			'statement_import.confirm.breakdown_expense' => 'Expenses',
			'statement_import.confirm.breakdown_fees' => 'Fees',
			'statement_import.confirm.breakdown_total' => 'Net total',
			'statement_import.confirm.undo_hint' => 'If something is imported incorrectly you can undo from the account history in the next 7 days.',
			'statement_import.confirm.back' => 'Back',
			'statement_import.confirm.import_cta' => 'Import',
			'statement_import.confirm.error' => 'Could not save. Try again.',
			'statement_import.success.title' => ({required Object n}) => '${n} movements imported',
			'statement_import.success.view_history' => 'View in history',
			'statement_import.success.done' => 'Done',
			'statement_import.undo.banner_title' => 'Recent import',
			'statement_import.undo.banner_body' => ({required Object n, required Object date}) => '${n} movements · ${date}',
			'statement_import.undo.undo_cta' => 'Undo',
			'statement_import.undo.dialog_title' => 'Undo import?',
			'statement_import.undo.dialog_body' => ({required Object n}) => '${n} imported movements will be deleted.',
			'statement_import.undo.dialog_confirm' => 'Undo',
			'statement_import.undo.dialog_cancel' => 'Cancel',
			'statement_import.undo.success' => 'Import undone',
			'statement_import.entry_point' => 'Import account statement',
			'more.title' => 'More',
			'more.title_long' => 'More actions',
			'more.search.hint' => 'Search settings…',
			'more.sections.quick_access' => 'Quick access',
			'more.sections.management' => 'Management',
			'more.sections.configuration' => 'Configuration',
			'more.sections.data' => 'Data',
			'more.sections.tools' => 'Tools',
			'more.sections.about' => 'About',
			'more.account.sign_out' => 'Sign out',
			'more.account.sync_active' => 'Synced',
			'more.account.sync_inactive' => 'Sync disabled',
			'more.account.no_account' => 'No account linked',
			'more.account.fallback_name' => 'Your account',
			'more.account.firebase_sync' => 'Firebase Sync',
			'more.theme.title' => 'Theme',
			'more.theme.system' => 'System',
			'more.theme.light' => 'Light',
			'more.theme.dark' => 'Dark',
			'more.theme.amoled' => 'AMOLED mode',
			'more.theme.more_options' => 'More appearance options',
			'more.ai.title' => 'Bolsi',
			'more.ai.configure' => 'Set up your financial assistant',
			'more.ai.active_with' => 'Active · {provider}',
			'more.data.display' => 'Data',
			'more.data.display_descr' => 'Export and import your data so you don\'t lose anything',
			'more.data.delete_all' => 'Delete my data',
			'more.data.delete_all_header1' => 'Stop right there padawan ⚠️⚠️',
			'more.data.delete_all_message1' => 'Are you sure you want to continue? All your data will be permanently deleted and cannot be recovered',
			'more.data.delete_all_header2' => 'One last step ⚠️⚠️',
			'more.data.delete_all_message2' => 'By deleting an account you will delete all your stored personal data. Your accounts, transactions, budgets and categories will be deleted and cannot be recovered. Do you agree?',
			'more.about_us.display' => 'App information',
			'more.about_us.description' => 'Find Bolsio’s terms, important info, and connect by reporting bugs or sharing ideas',
			'more.about_us.legal.display' => 'Legal information',
			'more.about_us.legal.privacy' => 'Privacy policy',
			'more.about_us.legal.terms' => 'Terms of use',
			'more.about_us.legal.licenses' => 'Licenses',
			'more.about_us.project.display' => 'Project',
			'more.about_us.project.contributors' => 'Collaborators',
			'more.about_us.project.contributors_descr' => 'All the developers who have made Bolsio grow',
			'more.about_us.project.contact' => 'Contact us',
			'more.help_us.display' => 'Help us',
			'more.help_us.description' => 'Find out how you can help Bolsio become better and better',
			'more.help_us.rate_us' => 'Rate us',
			'more.help_us.rate_us_descr' => 'Any rate is welcome!',
			'more.help_us.share' => 'Share Bolsio',
			'more.help_us.share_descr' => 'Share our app to friends and family',
			_ => null,
		} ?? switch (path) {
			'more.help_us.share_text' => 'Bolsio! The best personal finance app. Download it here',
			'more.help_us.thanks' => 'Thank you!',
			'more.help_us.thanks_long' => 'Your contributions to Bolsio and other open source projects, big and small, make great projects like this possible. Thank you for taking the time to contribute.',
			'more.help_us.donate' => 'Make a donation',
			'more.help_us.donate_descr' => 'With your donation you will help the app continue receiving improvements. What better way than to thank the work done by inviting me to a coffee?',
			'more.help_us.donate_success' => 'Donation made. Thank you very much for your contribution! ❤️',
			'more.help_us.donate_err' => 'Oops! It seems there was an error receiving your payment',
			'more.help_us.report' => 'Report bugs, leave suggestions...',
			'onboarding.restricted_settings.title' => 'Allow restricted settings',
			'onboarding.restricted_settings.subtitle' => 'Android blocks some permissions for apps installed outside Play Store. We\'ll fix it in 3 taps.',
			'onboarding.restricted_settings.step1' => 'Tap the ⋮ menu in the top-right.',
			'onboarding.restricted_settings.step2' => 'Select "Allow restricted settings".',
			'onboarding.restricted_settings.step3' => 'Toggle it on and return to Bolsio.',
			'onboarding.restricted_settings.step1_xiaomi' => 'Scroll to the bottom of the page.',
			'onboarding.restricted_settings.step2_xiaomi' => 'Toggle on "Allow restricted settings".',
			'onboarding.restricted_settings.cta_primary' => 'Open app info',
			'onboarding.restricted_settings.cta_skip' => 'Skip for now',
			'onboarding.restricted_settings.cta_done' => 'Done, continue',
			'onboarding.restricted_settings.still_blocked_hint' => 'If you already enabled it, open app info again.',
			'onboarding.restricted_settings.success_toast' => 'Done, settings unlocked',
			_ => null,
		};
	}
}
