'use strict';

// @ngInject
function ColorPickerController() {
  this.colors = [
    'green',
    'yellow',
    'blue',
    'purple',
  ];

  this.color = this.colors[0];

  this.onColorChanged = function() {
    this.onEditColor({ color: this.color });
  };
}

module.exports = {
  controller: ColorPickerController,
  controllerAs: 'vm',
  bindings: {
    color: '<',
    onEditColor: '&',
  },
  template: require('../templates/color-picker.html'),
};
