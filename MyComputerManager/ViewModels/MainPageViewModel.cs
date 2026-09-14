using MyComputerManager.Helpers;
using MyComputerManager.Models;
using MyComputerManager.Mvvm;
using MyComputerManager.Services.Contracts;
using MyComputerManager.Views;
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Wpf.Ui.Appearance;
using Wpf.Ui.Common;
using Wpf.Ui.Controls;
using Wpf.Ui.Mvvm.Contracts;

namespace MyComputerManager.ViewModels
{
    public class MainPageViewModel : Wpf.Ui.Mvvm.ViewModelBase
    {
        private readonly INavigationService _navigationService;
        private readonly IDataService _dataService;
        private readonly ISnackBarService _snackBarService;
        private readonly IDialogService _dialogService;
        public MainPageViewModel(INavigationService navigationService, IDataService dataService, ISnackBarService snackBarService, IDialogService dialogService)
        {
            _navigationService = navigationService;
            _dataService = dataService;
            _snackBarService = snackBarService;
            _dialogService = dialogService;
            Items = (ObservableCollection<NamespaceItem>)_dataService.GetData();
            dataService.SetVM(this);
            GoDetailCommand = new RelayCommand(GoDetail);
            ToggleCommand = new RelayCommand(ToggleEnabled);
            BatchDeleteCommand = new AsyncRelayCommand(BatchDelete);
            BatchDisableCommand = new RelayCommand(BatchDisable);
            BatchEnableCommand = new RelayCommand(BatchEnable);
            ToggleSelectAllCommand = new RelayCommand(ToggleSelectAll);
            foreach (var item in Items)
            {
                item.PropertyChanged += Item_PropertyChanged;
            }
            Items.CollectionChanged += (s, e) =>
            {
                if (e.NewItems != null)
                {
                    foreach (NamespaceItem item in e.NewItems)
                        item.PropertyChanged += Item_PropertyChanged;
                }
                if (e.OldItems != null)
                {
                    foreach (NamespaceItem item in e.OldItems)
                        item.PropertyChanged -= Item_PropertyChanged;
                }
            };
        }

        private void Item_PropertyChanged(object sender, PropertyChangedEventArgs e)
        {
            if (e.PropertyName == "IsSelected")
            {
                IsAllSelected = Items.Count > 0 && Items.All(i => i.IsSelected);
            }
        }

        private ObservableCollection<NamespaceItem> items;

        public ObservableCollection<NamespaceItem> Items
        {
            get { return items; }
            set
            {
                items = value;
                this.OnPropertyChanged("Items");
            }
        }

        private bool isAllSelected;
        public bool IsAllSelected
        {
            get { return isAllSelected; }
            set
            {
                isAllSelected = value;
                this.OnPropertyChanged("IsAllSelected");
            }
        }

        public void GoDetail(object item)
        {
            _dataService.SetData(item);
            _navigationService.Navigate(typeof(DetailPage));
        }

        public RelayCommand GoDetailCommand { get; set; }
        public RelayCommand ToggleCommand { get; set; }
        public AsyncRelayCommand BatchDeleteCommand { get; set; }
        public RelayCommand BatchDisableCommand { get; set; }
        public RelayCommand BatchEnableCommand { get; set; }
        public RelayCommand ToggleSelectAllCommand { get; set; }

        public void ToggleEnabled(object obj)
        {
            NamespaceItem item = (NamespaceItem)obj;
            var res = NamespaceHelper.SetEnabled(item, item.IsEnabled);
            if (!res.success)
            {
                _snackBarService.Show("操作失败", res.result, SymbolRegular.ShieldError16);
                item.IsEnabled = !item.IsEnabled;
            }
        }

        public void ToggleSelectAll(object obj)
        {
            bool newValue = !IsAllSelected;
            foreach (var item in Items)
            {
                item.IsSelected = newValue;
            }
            IsAllSelected = newValue;
        }

        private List<NamespaceItem> GetSelectedItems()
        {
            return Items.Where(i => i.IsSelected).ToList();
        }

        public async Task BatchDelete()
        {
            var selected = GetSelectedItems();
            if (selected.Count == 0)
            {
                _snackBarService.Show("提示", "请先选择要删除的项目", SymbolRegular.Info16, ControlAppearance.Secondary, 3000);
                return;
            }

            var names = string.Join("、", selected.Select(i => i.Name ?? "未命名"));
            var res = _dialogService.ShowDialog(
                new DialogMessage("警告", $"此操作将删除以下 {selected.Count} 个项目，且无法恢复！\n\n{names}"),
                null,
                ControlAppearance.Danger, "确认删除",
                ControlAppearance.Transparent, "取消操作"
            );

            if (!res)
            {
                int successCount = 0;
                int failCount = 0;
                foreach (var item in selected)
                {
                    var result = NamespaceHelper.DeleteItem(item);
                    if (result.success)
                    {
                        successCount++;
                        Items.Remove(item);
                    }
                    else
                    {
                        failCount++;
                    }
                }

                if (failCount == 0)
                    _snackBarService.Show("操作成功", $"已删除 {successCount} 个项目", SymbolRegular.CheckmarkCircle16);
                else
                    _snackBarService.Show("部分操作失败", $"成功 {successCount} 个，失败 {failCount} 个", SymbolRegular.ShieldError16);
            }
        }

        public void BatchDisable()
        {
            var selected = GetSelectedItems();
            if (selected.Count == 0)
            {
                _snackBarService.Show("提示", "请先选择要禁用的项目", SymbolRegular.Info16, ControlAppearance.Secondary, 3000);
                return;
            }

            int successCount = 0;
            int failCount = 0;
            foreach (var item in selected)
            {
                if (!item.IsEnabled) continue;
                var res = NamespaceHelper.SetEnabled(item, false);
                if (res.success)
                {
                    successCount++;
                    item.IsEnabled = false;
                }
                else
                {
                    failCount++;
                }
            }

            if (failCount == 0)
                _snackBarService.Show("操作成功", $"已禁用 {successCount} 个项目", SymbolRegular.CheckmarkCircle16);
            else
                _snackBarService.Show("部分操作失败", $"成功 {successCount} 个，失败 {failCount} 个", SymbolRegular.ShieldError16);
        }

        public void BatchEnable()
        {
            var selected = GetSelectedItems();
            if (selected.Count == 0)
            {
                _snackBarService.Show("提示", "请先选择要启用的项目", SymbolRegular.Info16, ControlAppearance.Secondary, 3000);
                return;
            }

            int successCount = 0;
            int failCount = 0;
            foreach (var item in selected)
            {
                if (item.IsEnabled) continue;
                var res = NamespaceHelper.SetEnabled(item, true);
                if (res.success)
                {
                    successCount++;
                    item.IsEnabled = true;
                }
                else
                {
                    failCount++;
                }
            }

            if (failCount == 0)
                _snackBarService.Show("操作成功", $"已启用 {successCount} 个项目", SymbolRegular.CheckmarkCircle16);
            else
                _snackBarService.Show("部分操作失败", $"成功 {successCount} 个，失败 {failCount} 个", SymbolRegular.ShieldError16);
        }

        public void DeleteItem(NamespaceItem item)
        {
            if (item != null)
                if (Items.Contains(item))
                    Items.Remove(item);
        }

        public void AddItem(NamespaceItem item)
        {
            Items.Add(item);
        }
    }
}